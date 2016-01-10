#!/usr/local/bin/ruby
require 'yaml'
require 'pp'
require_relative '../rlib/configuration.rb' #need to replace with a gem

@config = Configuration.new('/usr/local/wikk/etc/pf/pf_line_ctl.json')
@line_ctl = Configuration.new("#{@config.conf_dir}/line_state.json")
@num_lines = @line_ctl.state.length - 1
@host_line_map = Configuration.new("#{@config.conf_dir}/host_line_map.json")

#Check that the xDSL modems are up, and connected to the ISP
adsl_pingable = []  #Can ping xDSL modem
line_active = []    #Can ping the external IP of the xDSL modem, so we know it should be connected to ISP

(1..@num_lines).each do |i|
 if @line_ctl.state[i]['line'] >= 1 #Then external xDSL line is present.
   system("/usr/local/sbin/fping -u adsl#{i}") #See if the modem is actually working
   adsl_return_code = $?
   adsl_pingable[i] = adsl_return_code.to_i == 0
   if adsl_pingable[i] 
     system("/usr/local/sbin/fping -u external#{i}") #see if line is connected to the ISP.
     ex_return_code = $?
     line_active[i] = ex_return_code.to_i == 0
     system("#{@config.bin_dir}/#{@line_ctl.state[i]['config_script']}") if @line_ctl.state[i]['config_script'] != nil && @line_ctl.state[i]['line'] == i
   else #Can't ping the xDSL router, so we wouldn't be able to ping the external line.
     line_active[i] = false
   end
 else #Line is administratively offline.
   adsl_pingable[i] = line_active[i] = false
 end
end

out = [] #This is the output queue.
(0..@num_lines).each { |i| out[i] = [] } #Base assumptions is all lines have array of clients, even if array empty.

processed = [] #These are lines that are up
missed = []    #These are site entries for lines that are down, hence need to be load balanced over other lines

#Assign users to lines, testing for line being up, and explicit mappings of entire lines to other lines
(1..@num_lines).each do |i|
 if(line_active[@line_ctl.state[i]['line']] && @host_line_map.line[i] != nil) #MAPPED LINE IS ACTIVE AND HAVE USER FOR THIS LINE
   @host_line_map.line[i].each { |host,network| out[@line_ctl.state[i]['line']] << [host,network, i] } #Populate out queue
   processed << i #Note that this line is up.
 else #A line is down, so assign the sites on this line to the missed queue
   if @host_line_map.line[i] != nil
     @host_line_map.line[i].each { |host,network| missed << [host,network,i] } #Note the sites on lines that are down
   end
 end
end


if processed.length > 0 #at least one line is up ;)
  #puts processed.length
  r = 0
  missed.each do |m| #process missed queue, adding members to the working lines in a round robin fashion.
    out[processed[r]] << m
    r = (r + 1) % processed.length 
  end
  
  #Now output the table_line_x (Pf tables to load with pf_ctl) and table_line_state_x (Web page status info) files.
  (1..@num_lines).each do |i|
    File.open("#{@config.tmp_dir}/table_line_#{i}", 'w') do |fd|
      out[i].each { |o| fd.puts "   #{o[1]}" } #Line per site, outputing the site network for pf to load into tables
    end
    File.open("#{@config.tmp_dir}/table_line_state_#{i}", 'w') do |fd|
      out[i].each do |o| 
        if i == o[2] #o[2] is the line this entry should have been on.
          fd.puts "#{o[0]}\t#{o[1]}\tblack" #o[0] is the site name. o[1] is the ip/maskbits, Black: site on prefered line.
        else
          fd.puts "#{o[0]}\t#{o[1]}\tred"    #o[0] is the site name. o[1] is the ip/maskbits. Red: site on alternate line.
        end
      end
    end
  end
else
  puts "All external lines are down"
  #As all lines are down, we assign networks to their default lines on the assumption that when the lines come back,
  #they will do so together, and it is best to have pf tables ready.
  (1..@num_lines).each do |i|
    File.open("#{@config.tmp_dir}/table_line_#{i}", 'w') do |fd|
      if @host_line_map.line[i] != nil
        @host_line_map.line[i].each { |host,network| fd.puts "   #{network}" } #Line per site, outputing the site ip/maskbits for pf to load into tables
      end
    end
    File.open("#{@config.tmp_dir}/table_line_state_#{i}", 'w') do |fd|
      if @host_line_map.line[i] != nil
        @host_line_map.line[i].each { |host,network| fd.puts "#{host}\t#{network}\tblack" } #Site, ip/maskbits, black for on correct line
      end
    end
  end
end
