#!/usr/local/ruby2.2/bin/ruby
require 'json'
require 'pp'
require 'mysql'
require_relative '../rlib/configuration.rb' #need to replace with a gem
require_relative '../rlib/json.rb' 

#How to find files and directories.
@config = Configuration.new('/usr/local/wikk/etc/pf/pf_line_ctl.json')
@mysql = Configuration.new('/usr/local/wikk/etc/keys/mysql.json')

line = []

my = Mysql::new(@mysql.host, @mysql.dbuser, @mysql.key, @mysql.db)
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

#Need to add locking around this, though it will self correct every few minutes.  
    File.open("#{@config.conf_dir}/host_line_map.json", "w") do |fd|
      #fd = $stdout
      fd.puts "{\n\"line\": "
      fd.puts line.to_j
      fd.puts "\n}\n"
    end
  end
end

