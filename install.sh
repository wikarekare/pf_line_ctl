#!/bin/sh
HOST="admin2"
	scp pf_daily.sh pf_line_ctl.rb pf_cron.sh pf_host_line_map_update.rb root@${HOST}:/usr/local/wikk/sbin
