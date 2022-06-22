#!/bin/bash
PF_CONF_DIR="/usr/local/wikk/etc/pf"
TMP_DIR="/usr/local/wikk/var/pf"
WWW_DIR="/services/www/wikarekare/line"
BIN_DIR="/usr/local/wikk/sbin"
#REMOTE_COPY="admin2"
REMOTE_COPY=""

if [ -e /dev/pf ]
then
    #Depends on https://github.com/rbur004/lockfile
    /usr/local/bin/lockfile ${TMP_DIR}/pf_cron.lock $$
    if [ $? != 0 ] ; then  exit 0 ; fi

    for i in 1 2 3 4 5 6; do
      /sbin/pfctl -t local_nets_${i} -T show | /usr/bin/sort > ${TMP_DIR}/local_nets_${i}
    done

    ${BIN_DIR}/pf_line_ctl.rb

    for i in 1 2 3 4 5 6; do
     /usr/bin/sort -u ${TMP_DIR}/table_line_${i} > ${TMP_DIR}/table_line_${i}.srt
    done

    #decommissioned lines 1 to 3
    #So only need to do this for lines 4 through 6
    for i in 4 5 6; do
      /usr/bin/cmp -s ${TMP_DIR}/local_nets_${i} ${TMP_DIR}/table_line_${i}.srt
      if [ $? != 0 ]
      then
              echo `/bin/date "+%Y-%m-%d %H:%M:%S"` " switching to " table_${i} >> /var/log/pfchange.log
              /sbin/pfctl -t local_nets_${i} -T replace -f ${TMP_DIR}/table_line_${i}.srt
      fi
    done

    if [ $REMOTE_COPY != "" ]
    then
        #Make copies on the web server, so we can easily access the current status.
        #Should be derived from DB, so web server would just do lookup
        for i in 1 2 3 4 5 6; do
          scp -i /home/wikk/.ssh/id_rsa  ${TMP_DIR}/table_line_${i}.srt ${LINE}@${REMOTE_COPY}:${WWW_DIR}/line${i}.txt
          scp -i /home/wikk/.ssh/id_rsa  ${TMP_DIR}/table_line_state_${i} ${LINE}@${REMOTE_COPY}:${WWW_DIR}/line${i}_state.txt
        done

        #Should be the other way around, and driven from the web interface, into the DB.
        scp -i /home/wikk/.ssh/id_rsa ${PF_CONF_DIR}/line_state.json ${PF_CONF_DIR}/host_line_map.json ${LINE}@${REMOTE_COPY}:${PF_CONF_DIR}/
    fi
    /bin/rm -f ${TMP_DIR}/pf_cron.lock
fi
