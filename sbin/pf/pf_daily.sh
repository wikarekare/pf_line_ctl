#!/bin/bash
. /wikk/etc/wikk.conf
SCP=/usr/bin/scp

LOCK_PID_FILE=${TMP_DIR}/pf_daily.lock
${LOCKFILE} ${LOCK_PID_FILE} $$
if [ $? != 0 ] ; then  exit 0 ; fi

${SBIN_DIR}/pf/pf_host_line_map_update.rb
# While other gate is inactive, comment out the sync. Should check this dynamically!
# ${SCP} -i ${SSH_KEY_DIR}/line_id_rsa ${PF_CONF_DIR}/host_line_map.json ${LINE}@${PF_HOST_1}:${PF_CONF_DIR_REMOTE}/host_line_map.json
${SCP} -i ${SSH_KEY_DIR}/line_id_rsa ${PF_CONF_DIR}/host_line_map.json ${LINE}@${PF_HOST_2}:${PF_CONF_DIR_REMOTE}/host_line_map.json

${RM} -f ${LOCK_PID_FILE}
