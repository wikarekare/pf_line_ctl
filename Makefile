all:
	echo "Only valid option is make install"

install:
	install pf_line_ctl.rb pf_cron.sh /usr/local/wikk/sbin
