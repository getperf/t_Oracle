#!/bin/sh
#
# This procedure check Oracle Segment size.
#

LANG=C;export LANG
CMDNAME=`basename $0`
CWD=`dirname $0`
USAGE="Usage: $CMDNAME [dir]"
SID=RTDYYY

ODIR=$1

# Y4CPU
sh $CWD/getorasql.sh -i ${SID} -l ${ODIR} -u rtdmgr/rtdmgr@RTDYYY -f rtd01_eqp_cnt
sh $CWD/getorasql.sh -i ${SID} -l ${ODIR} -u rtdmgr/rtdmgr@RTDYYY -f rtd02_eqp_grp_cnt
sh $CWD/getorasql.sh -i ${SID} -l ${ODIR} -u rtdmgr/rtdmgr@RTDYYY -f rtd04_etp_grp_ins_cnt
sh $CWD/getorasql.sh -i ${SID} -l ${ODIR} -u rtdmgr/rtdmgr@RTDYYY -f rtd05_eqp_grp_createjob_cnt
sh $CWD/getorasql.sh -i ${SID} -l ${ODIR} -u rtdmgr/rtdmgr@RTDYYY -f rtd06_eqp_grp_elapse
sh $CWD/getorasql.sh -i ${SID} -l ${ODIR} -u rtdmgr/rtdmgr@RTDYYY -f rtd07_eqp_grp_job_cnt

