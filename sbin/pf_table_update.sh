#!/bin/sh
#Run from cron on gateway host
#*/3 * * * * /wikk/sbin/pf/pf_table_update.sh > /wikk/var/tmp/pf_table_update.out 2>&1
#
#Updates the PF tables based on checks of the DSL modem connection state, and the
#customer network line map
#
. /wikk/etc/wikk.conf

#Depends on https://github.com/rbur004/lockfile
LOCK_PID_FILE=${TMP_DIR}/pf/pf_cron.lock
${LOCKFILE} ${LOCK_PID_FILE} $$
if [ $? != 0 ] ; then  exit 0 ; fi

if [ -e /dev/pf ]
then

    for i in 5 6 7; do
      if [ ! -e ${PF_WRK_DIR}/table_line_${i} ]
      then
        cp /dev/null ${PF_WRK_DIR}/table_line_${i}
      fi
      if [ ! -e ${PF_WRK_DIR}/table_line_state_${i} ]
      then
        cp /dev/null ${PF_WRK_DIR}/table_line_state_${i}
      fi
    done

    for i in 5 6 7; do
      ${PFCTL} -t local_nets_${i} -T show | ${SORT} > ${PF_WRK_DIR}/local_nets_${i}
    done

    ${SBIN_DIR}/pf/pf_line_ctl.rb

    for i in 5 6 7; do
     ${SORT} -u ${PF_WRK_DIR}/table_line_${i} > ${PF_WRK_DIR}/table_line_${i}.srt
    done

    #decommissioned lines 1 to 3
    #So only need to do this for lines 5 through 7
    for i in 5 6 7; do
      ${CMP} -s ${PF_WRK_DIR}/local_nets_${i} ${PF_WRK_DIR}/table_line_${i}.srt
      if [ $? != 0 ]
      then
              echo `${DATE} "+%Y-%m-%d %H:%M:%S"` " switching to " table_${i} >> ${PF_LOG_DIR}/pfchange.log
              ${PFCTL} -t local_nets_${i} -T replace -f ${PF_WRK_DIR}/table_line_${i}.srt
      fi
    done

    if [ "${WEB_SRV}" != "" -a "${ROLE}" == "PRIMARY_PF" ]
    then
        #Make copies on the web server, so we can easily access the current status.
        #Should be derived from DB, so web server would just do lookup
        echo "Copying line state files to web server"
        for i in 5 6 7; do
          scp -i /home/line/.ssh/id_rsa  ${PF_WRK_DIR}/table_line_${i}.srt line@${WWW_SRV}:line/line${i}.txt
          scp -i /home/line/.ssh/id_rsa  ${PF_WRK_DIR}/table_line_state_${i} line@${WWW_SRV}:line/line${i}_state.txt
        done
    else
            #Make copies on the web server, so we can easily access the current status.
        #Should be derived from DB, so web server would just do lookup
        for i in 5 6 7; do
          cp ${PF_WRK_DIR}/table_line_${i}.srt ${LINE_WWW_DIR}/line${i}.txt
          cp ${PF_WRK_DIR}/table_line_state_${i} ${LINE_WWW_DIR}/line${i}_state.txt
        done
    fi
fi

rm -f ${LOCK_PID_FILE}
