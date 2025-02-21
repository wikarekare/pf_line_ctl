#!/usr/local/bin/ruby
require 'json'
require 'wikk_configuration'
require 'wikk_json'

unless defined? WIKK_CONF
  load '/wikk/etc/wikk.conf'
end
require_relative "#{RLIB}/dsl/dsl_status.rb"

# Ping a host, and verify the return code
# @param host [String]
# @return [Boolean] True if pingable
def pingable?(host:)
  system("#{FPING} -u #{host}")
  $CHILD_STATUS.to_i == 0
end

def line_up?(host:)
  status = ADSL_Status.status(host)
  return status != nil && status['line_status'] == 'Up'
rescue StandardError
  return false
end

# Check that the xDSL modems are up, and connected to the ISP
# Sets @line_active[]
def check_line_state
  @line_active = []   # Can ping the external IP of the xDSL modem, so we know it should be connected to ISP
  adsl_pingable = []  # Can ping xDSL modem

  (1..@num_lines).each do |i| # Skip 0, as we start numbering dsl modems at 1, while the array numbers from 0
    # Check if xDSL line is administratively up, though it may still not be connected to ISP.
    if @line_ctl.line[i]['active']
      # See if the modem is actually working. Internal network test
      adsl_pingable[i] = pingable?(host: @line_ctl.line[i]['hostname'])
      if adsl_pingable[i] && @line_ctl.line[i]['up']
        # If line has a config script, run it. And we are the current 'gate' host
        if ROLE == 'PRIMARY_PF' && !@line_ctl.line[i]['config_script'].nil?
          puts "Running #{SBIN_DIR}/pf/#{@line_ctl.line[i]['config_script']}"
          begin
            `#{SBIN_DIR}/pf/#{@line_ctl.line[i]['config_script']}`
          rescue RuntimeError => e
            warn e.message
          rescue SystemCallError => e
            warn e.message
          end
        end

        # see if line is connected to the ISP. Have to know external IP address.
        @line_active[i] = line_up?(host: @line_ctl.line[i]['hostname']) && pingable?(host: "external#{i}")
      else # Can't ping the xDSL router, so we wouldn't be able to ping the external line.
        @line_active[i] = false # Line is inactive, as internal ping failed.
      end
      puts "#{@line_ctl.line[i]['hostname']} is active, state is administratively #{@line_ctl.line[i]['up'] ? 'up' : 'down'}, Pingable: #{adsl_pingable[i]}, Line_up: #{@line_active[i]}"
    else # Line is administratively offline. (Don't bother pinging it)
      adsl_pingable[i] = @line_active[i] = false
    end
  rescue StandardError => e
    warn "Error for line[#{i}]: #{e}"
    adsl_pingable[i] = @line_active[i] = false
  end
end

# Create a list of just the lines that are UP
# And create a failure map, for lines that are DOWN
# To make processing easier, lines that are UP to themselves
def build_line_failure_map
  @active_lines = [] # These are lines that are up
  @failure_map = [] # Map of line number allocated to sites, to active line number
  # Build failure mapping from inactive to active lines.
  (1..@num_lines).each do |i|
    @failure_map[i] = []
    if @line_active[i]
      @failure_map[i] << i # i.e. maps to itself, so we don't have to test later.
      @active_lines << i # Note that this line is up.
    elsif ! @line_ctl.line[i]['failure_map'].nil? # Not active, and has a fail over line defined.
      @line_ctl.line[i]['failure_map'].each do |m|
        @failure_map[i] << m if @line_active[m] # active lines in map replaces this one
      end
    end
  end
end

# Some lines are down, so reassign sites to the alternate lines for the failed line
def reassign_sites_to_active_lines
  missed = [] # These are site entries for lines that are down, hence need to be load balanced over other lines

  # Assign users to lines, testing for line being up, and explicit mappings of entire lines to other lines
  (1..@num_lines).each do |i|
    unless @host_line_map.line[i].nil? # Check if LINE Has sites assigned to it (even if the line is inactive)
      if !@failure_map[i].nil? && @failure_map[i].length > 0 # The line (or its alternate) is active
        index = 0
        @host_line_map.line[i].each do |host, network|
          target_line = index % @failure_map[i].length
          @out[@failure_map[i][target_line]] << [ host, network, i ] # Populate out queue with host, network and what the line should have been
          index += 1
        end
      else # the line is down, so assign the sites on this line to the missed queue
        @host_line_map.line[i].each do |host, network|
          missed << [ host, network, i ] # Note the sites on lines that are down, and have no defined alternate line.
        end
      end
    end
  end

  r = 0
  missed.each do |m| # process missed queue, adding members to the working lines in a round robin fashion.
    @out[@active_lines[r]] << m # Assign to the next active line
    r = (r + 1) % @active_lines.length # Round robin, through the active lines.
  end
end

# All lines are up, so assign sites to their primary line
def sites_to_original_lines
  (1..@num_lines).each do |i|
    next if @host_line_map.line[i].nil? # Check if LINE Has sites assigned to it (even if the line is inactive)

    @host_line_map.line[i].each do |host, network|
      @out[i] << [ host, network, i ] # Populate out queue with host, network and what the line should have been
    end
  end
end

# Which lines exist is defined here.
@line_ctl = WIKK::Configuration.new("#{PF_CONF_DIR}/line_state.json")
# number of defined, but not necessarily active, external lines.
@num_lines = @line_ctl.line.length - 1
# Which line a host uses (by default) is defined here
@host_line_map = WIKK::Configuration.new("#{PF_CONF_DIR}/host_line_map.json")

@out = [] # This is the output queue.
(0..@num_lines).each { |i| @out[i] = [] } # Base assumptions is all lines have array of clients, even if array empty.

check_line_state
build_line_failure_map
if @active_lines.length > 0 # at least one line is up ;)
  reassign_sites_to_active_lines
else
  warn 'All external lines are down'
  sites_to_original_lines
end

File.open("#{PF_WRK_DIR}/line_active.json", 'w') do |fd|
  fd.puts @line_active.to_j
end

# Now output the table_line_x (Pf tables to load with pf_ctl) and table_line_state_x (Web page status info) files.
(1..@num_lines).each do |i|
  # Table file for this line, holding the client site networks for pf to load into tables
  File.open("#{PF_WRK_DIR}/table_line_#{i}", 'w') do |fd|
    @out[i].each { |client| fd.puts "   #{client[1]}" } # client[1] is the site network ip/maskbits
  end

  # Web page status file, transferred to the Web server
  File.open("#{PF_WRK_DIR}/table_line_state_#{i}", 'w') do |fd|
    @out[i].each do |client|
      if i == client[2] # client[2] is the line this entry should have been on.
        # client[0] is the site name.
        # client[1] is the ip/maskbits
        # Black: indicates that the site on prefered line.
        fd.puts "#{client[0]}\t#{client[1]}\tblack"
      else
        # Red: site on alternate line.
        fd.puts "#{client[0]}\t#{client[1]}\tred"
      end
    end
  end
end
