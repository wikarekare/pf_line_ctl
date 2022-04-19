#!/usr/local/bin/ruby
require 'json'
require 'pp'
require 'mysql'
require 'wikk_configuration'
require 'wikk_json'
RLIB='../../rlib'
require_relative "#{RLIB}/wikk_conf.rb"  

#How to find files and directories.
@mysql_conf = WIKK::Configuration.new(MYSQL_CONF)

line = []

my = Mysql::new(@mysql_conf.host, @mysql_conf.dbuser, @mysql_conf.key, @mysql_conf.db)
if my != nil
  res1 = my.query("select link, site_name, inet_ntoa(dns_network.network + subnet * subnet_size) as network, subnet_mask_bits from dns_network join dns_subnet using (dns_network_id) join customer_dns_subnet on (dns_subnet.dns_subnet_id = customer_dns_subnet.dns_subnet_id ) join customer using (customer_id) where dns_subnet.state = 'active' and customer.active = 1 order by link,site_name" )
  #Only write output if we got rows
  if res1.num_rows > 0
    res1.each do |row|
      line_index = row[0].to_i
      if line[line_index] == nil
        line[line_index] = {row[1] => "#{row[2]}/#{row[3]}"}
      else
        line[line_index][row[1]] = "#{row[2]}/#{row[3]}"
      end
    end
  
    File.open("#{PF_CONF_DIR}/host_line_map.json", "w") do |fd|
      #fd = $stdout
      fd.puts "{\n\"line\": "
      fd.puts line.to_j
      fd.puts "\n}\n"
    end
  end
end

