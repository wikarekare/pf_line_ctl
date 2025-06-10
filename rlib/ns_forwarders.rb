# Handle dynamic link allocation to DNS forwarders
# This alters the forwarding tables in /wikk/var/pf
# These files then replace the tables in /etc/pf.conf, every 3 minutes
class NS_Forwarders
  CURRENT_FORWARD_MAP = "#{PF_WRK_DIR}/ns_forwarder_map.json"

  # @param line_ctl [Array] of hashes for the current line state
  def initialize(line_ctl: )
    @line_ctl = line_ctl
    @num_lines = @line_ctl.line.length - 1
    create_forwarder_map(filename: CURRENT_FORWARD_MAP)
    set_pingable
  end

  # associate a name server forwarder with one of our lines
  # Lets us have multiple paths out
  def change_ns_forwarder_line(line_active:)
    @line_ctl.each_with_index do |_lctl, _i|
      unless @current_forwarder_map['ns_forwarder'].nil? # Skip the unconfigured ones
        # Do something
      end
    end
  end

  def set_pingable
    @current_forwarder_map.each do |cfm|
      cfm['pingable'] = cfm['ns_forwarder'].nil? ? false : pingable?(host: cfm['ns_forwarder'])
    end
  end

  # Create a new forwarder map, if one doesn't exist
  # Otherwise load the map from the file
  private def create_forwarder_map(filename:)
    if File.size?(filename).nil?
      # Assume the current line is the one the ns_forwarder is defined on
      # Assume the forwarder IP is pingable via the configured line
      # Correct later.
      @current_forwarder_map = @line_ctl.map.with_index { |lctl, i| { 'ns_forwarder' => lctl['ns_forwarder'], 'current_line' => i, 'pingable' => true } }
      save_current_forwarder_lines(filename: filename)
    else
      load_forwarder_map(filename: filename)
    end
  end

  # Read in last saved NS Forwarder map.
  # Forwarder map is the NS_Forwarder to line
  private def load_forwarder_map(filename: )
    @current_forwarder_map = WIKK::Configuration.new(filename)
  end

  # Save the forwarder map to disk
  private def save_current_forwarder_lines(filename:)
    File.open(filename, 'w') do |fd|
      fd.puts @current_forwarder_map.to_j
    end
  end

  # Ping a host, and verify the return code
  # @param host [String]
  # @return [Boolean] True if pingable
  private def pingable?(host:)
    system("#{FPING} -u #{host}")
    return $CHILD_STATUS.to_i == 0
  end
end
