#!/usr/local/bin/ruby
require 'json'
require 'pp'
require 'wikk_sql'
require 'wikk_configuration'
require 'wikk_json'

load '/wikk/etc/wikk.conf' unless defined? WIKK_CONF

# How to find files and directories.
@mysql_conf = WIKK::Configuration.new(MYSQL_CONF)

line = []

WIKK::SQL.connect(@mysql_conf) do |sql|
  query = <<~SQL
    SELECT link, site_name, inet_ntoa(dns_network.network + subnet * subnet_size) AS network, subnet_mask_bits
    FROM dns_network JOIN dns_subnet USING (dns_network_id)
    JOIN customer_dns_subnet ON (dns_subnet.dns_subnet_id = customer_dns_subnet.dns_subnet_id )
    JOIN customer USING (customer_id)
    WHERE dns_subnet.state = 'active' AND customer.active = 1
    ORDER BY link,site_name
  SQL
  sql.each_hash(query) do |row|
    line_index = row['link'].to_i
    line[line_index] ||= {}
    line[line_index][row['site_name']] = "#{row['network']}/#{row['subnet_mask_bits']}"
  end

  # Only write output if we got rows
  unless line.empty?
    File.open("#{PF_CONF_DIR}/host_line_map.json", 'w') do |fd|
      # fd = $stdout
      fd.print <<~JSON
        {
          "line":
          #{line.to_j}
        }
      JSON
    end
  end
end
