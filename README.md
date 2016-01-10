# pf_line_ctl
Scripts to control pf tables, hence which xDSL line a site uses

Configuration defined in 4 files. 

#pf_line_ctl.json

Defines where the directories are
```
{
  "conf_dir": "/usr/local/wikk/etc/pf",
  "tmp_dir": "/usr/local/wikk/var/pf",
  "bin_dir": "/usr/local/wikk/sbin"
}
```

#line_state.json

This file is generated from the DB so the gateway doesn't need to keep referencing the DB. It is mostly static.

Defines which lines exist; which line gets used when a site is assigned to a line; any script associated with activating a line.
In this case, line 0 has never existed; line 1-3 have been terminated; line 4 - 6 exist, but sites using line 5 have been administratively moved to line 6, while line 5 is being worked on (**Nb**. *The line 5 script wont run when the line specified is not 5* ).
```
{ 
  "state": [ 
      { "line": 0, "config_script": null},   //No line 0
      { "line": -1, "config_script": null},  //Line 1, disconnected
      { "line": -1, "config_script": null}, //Line 2, disconnected
      { "line": -1, "config_script": null}, //Line 3, disconnected
      { "line": 4, "config_script": null},   //clients allocate to line 4 should use this line
      { "line": 6, "config_script": "zyxel_fix_iptables.rb"},   //clients allocate to line 5 should use this line.
      { "line": 6, "config_script": null }   //clients allocate to line 6 should use this line (which could be another line)
  ]
}
```

#host_line_map.json

This file is generated from the DB so the gateway doesn't need to keep referencing to DB. It is mostly static.

Defines which site uses which of the xDSL lines.
```
{ "line":
  [
    {}, //Line 0
    {}, //Line 1
    {}, //Line 2
    {}, //Line 3
    {   //Line 4
       "site018": "10.100.1.96/27",
...
       "site190": "10.103.1.64/27"
    },
    {  //Line 5
      "site005": "10.243.1.192/24",
...
      "site092": "10.207.4.160/27"
    },
    { //Line 6
      "site100": "10.192.1.96/27",
...
      "site140": "10.184.1.224/27"
    }
  ]
}
```

#/etc/pf.conf

The gateway is an openBSD 5.4 pf firewall, with tables predefined to control the packet routing.  These tables get overwritten by the pf_cron.sh script, if they differ from the DB view of the tables. The default values allow startup traffic.

e.g.
```
adsl_gw4="192.168.1.4"
vdsl_gw5="192.168.1.25"
vdsl_gw6="192.168.1.26"
...
#Nets to use the first ADSL line
table <local_nets_1> persist { }
table <local_nets_2> persist { }
table <local_nets_3> persist { }
table <local_nets_4> persist {  $admin_net }
table <local_nets_5> persist { $gateway_net $site003_net }
table <local_nets_6> persist {  }
...
```

And rules to specify the route based on these tables. eg.
```
pass out log quick on $adsl_if1 inet proto { udp tcp } from { <local_nets_4> } to any port $dns_ports flags S/SA keep state queue(adsl4_dns, adsl4_tcpack_o) route-to { ($adsl_if1 $adsl_gw4) }
pass out log quick on $adsl_if1 inet proto { udp tcp } from { <local_nets_5> } to any port $dns_ports flags S/SA keep state queue(adsl5_dns, adsl5_tcpack_o) route-to { ($adsl_if1 $vdsl_gw5) }
pass out log quick on $adsl_if1 inet proto { udp tcp } from { <local_nets_6> } to any port $dns_ports flags S/SA keep state queue(adsl6_dns, adsl6_tcpack_o) route-to { ($adsl_if1 $vdsl_gw6) }
```
