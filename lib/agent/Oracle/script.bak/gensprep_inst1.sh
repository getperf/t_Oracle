#!/bin/sh
#
# This procedure execute Oracle statspack snap and report.
#

LANG=C;export LANG
COLUMNS=160;export COLUMNS
#resize -s 100 160
CMDNAME=`basename $0`
USAGE="Usage: $CMDNAME [-s] [-n purge_level] [-u user/pass@tns] [-c category] [-i sid] [-l dir] [-v snapshot_level] [-e errfile] [-x]"

# Set default param
CWD=`dirname $0`
MODE=
USER=perfstat/perfstat
PURGE=YES
PURGE_LEVEL=0
CATEGORY="ORACLE"
SNAPSHOT_LEVEL=5
CHECK_PROCESS=YES

# Oracle RAC Option
# If there are Oracle RAC Enviroment, this parameter should set 1 or 2 or ... with each node
INSTANCE_NUM=2		

DIR=.
SID=
ERR=/dev/null

# Get command option
OPT=
while getopts sn:c:l:i:v:e:u:x OPT
do
	case $OPT in
	x)	CHECK_PROCESS="NO"
		;;
	s)	MODE="RUNSNAP"
		;;
	n)	PURGE_LEVEL=$OPTARG
		;;
	l)	DIR=$OPTARG
		;;
	i)	SID=$OPTARG
		;;
	v)	SNAPSHOT_LEVEL=$OPTARG
		;;
	u)	USER=$OPTARG
		;;
	c)	CATEGORY=$OPTARG
		;;
        e)	ERR=$OPTARG
		;;
	\?)	echo "$USAGE" 1>&2
		exit 1
		;;
	esac
done
shift `expr $OPTIND - 1`

# Set current Date & Time
WORK="${CWD}/../_wk"

if [ ! -d ${WORK} ]; then
	/bin/mkdir -p ${WORK}
fi

# --------- Oracle 環境変数設定 --------------
. ${CWD}/oracle_env

# Check Oracle process
if [ "YES" = "${CHECK_PROCESS}" ]; then
	ORACLE_SID=${SID}; export ORACLE_SID
	/bin/ps -ef | grep ora_smon_${SID} > ${WORK}/ora_ps_${CATEGORY}_${SID}
	ORAPROC=`perl -ne 'print $1 if ($_=~/ora_smon_(.*)/ && $_!=~/grep/);' ${WORK}/ora_ps_${CATEGORY}_${SID}` 
	if [ "${ORACLE_SID}" != "${ORAPROC}" ]; then
		echo "ORACLE(${ORACLE_SID}) not found."
		exit 1
	fi
fi

# Check Oracle scripts
if [ ! -f ${CWD}/spreport.sql ]; then
	echo "File not fount: ${CWD}/spreport.sql"
	echo "gensprep.sh needs ; spreport.sql, sppurge.sql, sqlrank.sql ."
	exit 1
fi

if [ ! -f ${CWD}/sppurge.sql ]; then
	echo "File not fount: ${CWD}/sppurge.sql"
	echo "gensprep.sh needs ; spreport.sql, sppurge.sql, sqlrank.sql ."
	exit 1
fi

if [ ! -f ${CWD}/sqlrank.sql ]; then
	echo "File not fount: ${CWD}/sqlrank.sql"
	echo "gensprep.sh needs ; spreport.sql, sppurge.sql, sqlrank.sql ."
	exit 1
fi

# Execute snap of statspack

if [ "RUNSNAP" = "${MODE}" ]; then
	sqlplus ${USER} << EOF1 > ${ERR} 2>&1
	exec statspack.snap(i_snap_level=>${SNAPSHOT_LEVEL});
EOF1
fi

# Open "snpids" work file

NSNAPID=0
if [ -f ${WORK}/snapids_${CATEGORY}_${SID} ]; then
	exec 3<&0 < ${WORK}/snapids_${CATEGORY}_${SID}
	while read ID
	do
		NSNAPID=`expr $NSNAPID + 1`
		eval SNAP_$NSNAPID='"$ID"'
	done
fi

# Get newest snap_id from Statspack
sqlplus ${USER} << EOF2 > ${ERR} 2>&1
spool ${WORK}/newid.$$
select 'NEWEST_SNAPID '||max(snap_id) snap_id from stats\$snapshot where INSTANCE_NUMBER=${INSTANCE_NUM};
spool off
EOF2
perl -ne 'print $1 if /^NEWEST_SNAPID (\d+)/' ${WORK}/newid.$$ > ${WORK}/newid2.$$

if [ -f ${WORK}/newid2.$$ ]; then
	NEW_ID=`cat ${WORK}/newid2.$$`
else
	echo "newid not found."
	exit 1
fi
/bin/rm -f ${WORK}/newid*.$$

eval OLD_ID=\$SNAP_$NSNAPID

# Report statspack
if [ 0 -lt "${NSNAPID}" -a "${OLD_ID}" -lt "${NEW_ID}" ]; then
	{
cd ${CWD}
sqlplus ${USER} << EOF > ${ERR} 2>&1
define begin_snap=${OLD_ID}
define end_snap=${NEW_ID}
define report_name=${DIR}/spreport_${SID}
@spreport
EOF

# Report SQL Ranking when snapshot level >= 5
# if [ 5 -ge ${SNAPSHOT_LEVEL} ]; then
if [ ${SNAPSHOT_LEVEL} -ge 5 ]; then
	# Exec SQL Ranking report
	ORACMD="${CWD}/chcsv $USER -i ${CWD}/sqlrank.sql -o ${DIR}/sqlrank.txt ${OLD_ID} ${NEW_ID} > ${ERR} 2>&1"
	${ORACMD} >> ${ERR}
fi

	}
else
	echo "No newest snapshot report."
fi

# Purge snapshot
if [ 0 -lt $NSNAPID -a 0 -lt "${PURGE_LEVEL}" ]; then

	# Get oldest snap_id form Statspack
sqlplus ${USER} << EOF2 > ${ERR} 2>&1
spool ${WORK}/snapid.$$
select 'SNAPID '||min(snap_id) snap_id from stats\$snapshot  where INSTANCE_NUMBER=${INSTANCE_NUM};
spool off
EOF2
	OLDEST_ID=`perl -ne 'print $1 if /^SNAPID (\d+)/' ${WORK}/snapid.$$`
	/bin/rm -f ${WORK}/snapid.$$

	PURGE_ID=`expr $OLD_ID - $PURGE_LEVEL`

	if [ "${OLDEST_ID}" -ge "${PURGE_ID}" ]; then
		echo "No target of purge snapshot."
	else
	{
cd ${CWD}
sqlplus ${USER} << EOF3 >> ${ERR} 2>&1
define losnapid=${OLDEST_ID}
define hisnapid=${PURGE_ID}
@${CWD}/sppurge 
EOF3

	}
	fi
else
	echo "No purge snapshot id."
fi

# Close "snpids" work file
ID=`expr $NSNAPID - 1000`
if [ 0 -gt "${ID}" ]; then
	ID=1
fi

if [ -f ${WORK}/snapids_${CATEGORY}_${SID}_tmp ]; then
	/bin/rm -f ${WORK}/snapids_${CATEGORY}_${SID}_tmp
fi

while [ ${ID} -le ${NSNAPID} ]; 
do
	eval TMP_ID=\$SNAP_$ID
	echo ${TMP_ID} >> ${WORK}/snapids_${CATEGORY}_${SID}_tmp
	ID=`expr $ID + 1`
done

if [ "${OLD_ID}" -lt "${NEW_ID}" ]; then
	echo $NEW_ID >> ${WORK}/snapids_${CATEGORY}_${SID}_tmp
fi
/bin/mv -f ${WORK}/snapids_${CATEGORY}_${SID}_tmp ${WORK}/snapids_${CATEGORY}_${SID}

exit 0


