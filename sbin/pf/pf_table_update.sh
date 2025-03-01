#!/bin/bash
#Run from cron on gateway host
#*/3 * * * * /wikk/sbin/pf/pf_table_update.sh > /wikk/var/tmp/pf_table_update.out 2>&1
#
#Updates the PF tables based on checks of the DSL modem connection state, and the
#customer network line map
#
. /wikk/etc/wikk.conf
SCP=/usr/bin/scp

#Depends on https://github.com/rbur004/lockfile
LOCK_PID_FILE=${TMP_DIR}/pf/pf_cron.lock
${LOCKFILE} ${LOCK_PID_FILE} $$
if [ $? != 0 ] ; then  exit 0 ; fi

active_lines=$(/wikk/sbin/pf/active_lines.rb)
all_lines=$(/wikk/sbin/pf/all_lines.rb)

if [ -e /dev/pf ]
then

    for i in $all_lines ; do
      if [ ! -e ${PF_WRK_DIR}/table_line_${i} ]
      then
        ${CP} /dev/null ${PF_WRK_DIR}/table_line_${i}
      fi
      if [ ! -e ${PF_WRK_DIR}/table_line_state_${i} ]
      then
        ${CP} /dev/null ${PF_WRK_DIR}/table_line_state_${i}
      fi
    done

    for i in $all_lines ; do
      ${PFCTL} -t local_nets_${i} -T show | ${SORT} > ${PF_WRK_DIR}/local_nets_${i}
    done

    # This checks the line status to see what is actually up.
    ${SBIN_DIR}/pf/pf_line_ctl.rb

    for i in $active_lines ; do
     ${SORT} -u ${PF_WRK_DIR}/table_line_${i} > ${PF_WRK_DIR}/table_line_${i}.srt
    done

    #decommissioned lines 1 to 3
    #So only need to do this for lines 5 through 7
    for i in $active_lines ; do
      ${CMP} -s ${PF_WRK_DIR}/local_nets_${i} ${PF_WRK_DIR}/table_line_${i}.srt
      if [ $? != 0 ]
      then
              echo `${DATE} "+%Y-%m-%d %H:%M:%S"` " switching to " table_${i} >> ${PF_LOG_DIR}/pfchange.log
              ${PFCTL} -t local_nets_${i} -T replace -f ${PF_WRK_DIR}/table_line_${i}.srt
      fi
    done

    if [ "${WEB_SRV}" != "" -a "${ROLE}" == "PRIMARY_PF" ]
    then
        #Make copies on the remote web server, so we can easily access the current status.
        #Should be derived from DB, so web server would just do lookup
        echo "Copying line state files to web server"
        ${SCP} -i /home/line/.ssh/id_rsa  ${PF_WRK_DIR}/line_active.json ${LINE}@${WWW_SRV}:line/line_active.json
        for i in $active_lines ; do
          ${SCP} -i /home/line/.ssh/id_rsa  ${PF_WRK_DIR}/table_line_${i}.srt ${LINE}@${WWW_SRV}:line/line${i}.txt
          ${SCP} -i /home/line/.ssh/id_rsa  ${PF_WRK_DIR}/table_line_state_${i} ${LINE}@${WWW_SRV}:line/line${i}_state.txt
        done
    else
        #Make copies in the local web server dir
        #Should be derived from DB, so web server would just do lookup
        for i in $active_lines ; do
          ${CP} ${PF_WRK_DIR}/table_line_${i}.srt ${LINE_WWW_DIR}/line${i}.txt
          ${CP} ${PF_WRK_DIR}/table_line_state_${i} ${LINE_WWW_DIR}/line${i}_state.txt
        done
    fi
fi

${RM} -f ${LOCK_PID_FILE}
