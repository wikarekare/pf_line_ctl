#!/usr/local/bin/ruby
require 'json'
require 'pp'
require 'wikk_configuration'
require 'wikk_json'
RLIB = '../../rlib'
require_relative "#{RLIB}/wikk_conf.rb"

# Which lines exist is defined here.
@line_ctl = WIKK::Configuration.new("#{PF_CONF_DIR}/line_state.json")
@num_lines = @line_ctl.line.length - 1 # number of defined, but not necessarily active, external lines.

# Which line a host uses (by default) is defined here
@host_line_map = WIKK::Configuration.new("#{PF_CONF_DIR}/host_line_map.json")

# Check that the xDSL modems are up, and connected to the ISP
adsl_pingable = []  # Can ping xDSL modem
line_active = []    # Can ping the external IP of the xDSL modem, so we know it should be connected to ISP

(1..@num_lines).each do |i| # Skip 0, as we start numbering dsl modems at 1, while the array numbers from 0
  begin
    # Check if xDSL line is administratively up, though it may still not be connected to ISP.
    if @line_ctl.line[i]['active']
      # See if the modem is actually working. Internal network test
      system("#{FPING} -u #{@line_ctl.line[i]['hostname']}")
      adsl_return_code = $?
      adsl_pingable[i] = adsl_return_code.to_i == 0
      puts "#{@line_ctl.line[i]['hostname']} is active, state is administratively #{@line_ctl.line[i]['up'] ? 'up' : 'down'}, Pingable #{adsl_pingable[i]}"
      if adsl_pingable[i] && @line_ctl.line[i]['up']
        # If line has a config script, run it.
        if ROLE == 'PRIMARY_PF' && @line_ctl.line[i]['config_script'] != nil
          puts "Running #{SBIN_DIR}/pf/#{@line_ctl.line[i]['config_script']}"
          system("#{SBIN_DIR}/pf/#{@line_ctl.line[i]['config_script']}")
        end

        # see if line is connected to the ISP. Have to know external IP address.
        system("#{FPING} -u external#{i}")
        ex_return_code = $?
        line_active[i] = ex_return_code.to_i == 0 # Line is active, as internal and external ping worked.
      else # Can't ping the xDSL router, so we wouldn't be able to ping the external line.
        line_active[i] = false # Line is inactive, as internal ping failed.
      end
    else # Line is administratively offline. (Don't bother pinging it)
      adsl_pingable[i] = line_active[i] = false
    end
  rescue Exception => e
    puts "Error for line[#{i}]: #{e}"
    adsl_pingable[i] = line_active[i] = false
  end
end

active_lines = [] # These are lines that are up
failure_map = [] # Map of line number allocated to sites, to active line number
# Build failure mapping from inactive to active lines.
(1..@num_lines).each do |i|
  failure_map[i] = []
  if line_active[i]
    failure_map[i] << i # i.e. maps to itself, so we don't have to test later.
    active_lines << i # Note that this line is up.
  elsif @line_ctl.line[i]['failure_map'] != nil # Line is inactive
    @line_ctl.line[i]['failure_map'].each do |m|
      if line_active[m] # active lines in map replaces this one
        failure_map[i] << m
      end
    end # But has a fail over line defined.
  end
end

out = [] # This is the output queue.
(0..@num_lines).each { |i| out[i] = [] } # Base assumptions is all lines have array of clients, even if array empty.

missed = []    # These are site entries for lines that are down, hence need to be load balanced over other lines

# Assign users to lines, testing for line being up, and explicit mappings of entire lines to other lines
(1..@num_lines).each do |i|
  if @host_line_map.line[i] != nil # LINE Has sites assigned to it (even if the line is inactive)
    if failure_map[i] != nil && failure_map[i].length > 0 # The line (or its alternate) is active
      index = 0
      @host_line_map.line[i].each do |host, network|
        target_line = index % failure_map[i].length
        out[failure_map[i][target_line]] << [ host, network, i ] # Populate out queue with host, network and what the line should have been
        index += 1
      end
    else # A line is down, so assign the sites on this line to the missed queue
      @host_line_map.line[i].each do |host, network|
        missed << [ host, network, i ] # Note the sites on lines that are down, and have no defined alternate line.
      end
    end
  end
end

if active_lines.length > 0 # at least one line is up ;)
  r = 0
  missed.each do |m| # process missed queue, adding members to the working lines in a round robin fashion.
    out[active_lines[r]] << m # Assign to the next active line
    r = (r + 1) % active_lines.length # Round robin, through the active lines.
  end

  # Now output the table_line_x (Pf tables to load with pf_ctl) and table_line_state_x (Web page status info) files.
  (1..@num_lines).each do |i|
    File.open("#{PF_WRK_DIR}/table_line_#{i}", 'w') do |fd|
      out[i].each { |o| fd.puts "   #{o[1]}" } # Line per site, outputing the site network for pf to load into tables
    end
    File.open("#{PF_WRK_DIR}/table_line_state_#{i}", 'w') do |fd|
      out[i].each do |o|
        if i == o[2] # o[2] is the line this entry should have been on.
          fd.puts "#{o[0]}\t#{o[1]}\tblack" # o[0] is the site name. o[1] is the ip/maskbits, Black: site on prefered line.
        else
          fd.puts "#{o[0]}\t#{o[1]}\tred"    # o[0] is the site name. o[1] is the ip/maskbits. Red: site on alternate line.
        end
      end
    end
  end
else
  puts 'All external lines are down'
  # As all lines are down, we assign networks to their default lines on the assumption that when the lines come back,
  # they will do so together, and it is best to have pf tables ready.
  (1..@num_lines).each do |i|
    File.open("#{PF_WRK_DIR}/table_line_#{i}", 'w') do |fd|
      if @host_line_map.line[i] != nil
        @host_line_map.line[i].each { |_host, network| fd.puts "   #{network}" } # Line per site, outputing the site ip/maskbits for pf to load into tables
      end
    end
    File.open("#{PF_WRK_DIR}/table_line_state_#{i}", 'w') do |fd|
      if @host_line_map.line[i] != nil
        @host_line_map.line[i].each { |host, network| fd.puts "#{host}\t#{network}\tblack" } # Site, ip/maskbits, black for on correct line
      end
    end
  end
end
