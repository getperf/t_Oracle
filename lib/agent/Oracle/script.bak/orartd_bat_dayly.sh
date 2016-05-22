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

# Y4CPU1
sh $CWD/getorasql.sh -i ${SID} -l ${ODIR} -u rtdmgr/rtdmgr@RTDYYY -f rtd03_eqp_grp_list
sh $CWD/getorasql.sh -i ${SID} -l ${ODIR} -u rtdmgr/rtdmgr@RTDYYY -f rtd08_eqp_grp_rule
