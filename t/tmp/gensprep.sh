#!/bin/sh
#
# This procedure execute Oracle statspack snap and report.
#

LANG=C;export LANG
COLUMNS=160;export COLUMNS
#resize -s 100 160
CMDNAME=`basename $0`
USAGE="Usage: $CMDNAME [-s] [-n purge_level] [-c category] [-i sid] [-l dir] [-v snapshot_level] [-e errfile]"

# Set default param
CWD=`dirname $0`
MODE=
PURGE=YES
PURGE_LEVEL=0
CATEGORY="ORACLE"
SNAPSHOT_LEVEL=5
USER=perfstat/perfstat
DIR=.
SID=URA
ERR=/dev/null

# Get command option
OPT=
while getopts sn:c:l:i:v:e:u: OPT
do
	case $OPT in
	s)	MODE="RUNSNAP"
		;;
	n)	PURGE_LEVEL=$OPTARG
		;;
	l)	DIR=$OPTARG
		;;
	i)	SID=$OPTARG
		;;
	u)	USER=$OPTARG
		;;
	v)	SNAPSHOT_LEVEL=$OPTARG
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
LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${CWD}/../lib
export LD_LIBRARY_PATH

# Check Oracle process
ORACLE_SID=${SID}; export ORACLE_SID
#/bin/ps -ef | grep ora_smon_${SID} > ${WORK}/ora_ps_${CATEGORY}_${SID}
#ORAPROC=`perl -ne 'print $1 if ($_=~/ora_smon_(.*)/ && $_!=~/grep/);' ${WORK}/ora_ps_${CATEGORY}_${SID}` 
#if [ "${ORACLE_SID}" != "${ORAPROC}" ]; then
#	echo "ORACLE(${ORACLE_SID}) not found."
#	exit 1
#fi

#
# NY2 Service check
#
# Check y2im08db01b server abailable.
# inet 10.152.16.68 netmask fffff800 broadcast 10.152.23.255
# inet 192.168.10.42 netmask ffffff00 broadcast 192.168.10.255
# inet 10.53.215.208 netmask ffffff00 broadcast 10.53.215.255

	CHECK_NET_IF=`/sbin/ifconfig -a | grep 10.152.16.68`
	if [ "" = "$CHECK_NET_IF" ]; then
		echo "ORACLE(${ORACLE_SID}) not found."
		exit 0
	fi



# '10.152.16.71' => 'db_star_s',
# '10.152.16.72' => 'db_rtd_s',
# '10.152.16.73' => 'db_ura_s',

	# if [ "${SID}" = "Y2STAR"  ]; then
	# 	CHECK_NET_IF=`/sbin/ifconfig -a | grep 10.152.16.71`
	# 	if [ "" = "$CHECK_NET_IF" ]; then
	# 		echo "ORACLE(${ORACLE_SID}) not found."
	# 		exit 0
	# 	fi
	# fi

	# if [ "${SID}" = "Y2RTD" ]; then
	# 	CHECK_NET_IF=`/sbin/ifconfig -a | grep 10.152.16.72`
	# 	if [ "" = "$CHECK_NET_IF" ]; then
	# 		echo "ORACLE(${ORACLE_SID}) not found."
	# 		exit 0
	# 	fi
	# fi

	# if [ "${SID}" = "Y2URA0" ]; then
	# 	CHECK_NET_IF=`/sbin/ifconfig -a | grep 10.152.16.73`
	# 	if [ "" = "$CHECK_NET_IF" ]; then
	# 		echo "ORACLE(${ORACLE_SID}) not found."
	# 		exit 0
	# 	fi
	# fi

	# if [ "${SID}" = "Y2YOKMST" ]; then
	# 	CHECK_NET_IF=`/sbin/ifconfig -a | grep 10.152.16.73`
	# 	if [ "" = "$CHECK_NET_IF" ]; then
	# 		echo "ORACLE(${ORACLE_SID}) not found."
	# 		exit 0
	# 	fi
	# fi


# Execute snap of statspack

if [ "RUNSNAP" = "${MODE}" ]; then
	sqlplus $USER << EOF1 > $ERR 2>&1
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
sqlplus $USER << EOF2 > $ERR 2>&1
spool ${WORK}/newid.$$
select 'NEWEST_SNAPID '||max(snap_id) snap_id from stats\$snapshot;
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
sqlplus $USER << EOF > $ERR 2>&1
define begin_snap=${OLD_ID}
define end_snap=${NEW_ID}
define report_name=${DIR}/spreport_${SID}
@spreport
EOF
/bin/date '+END   REP  %y/%m/%d %H:%M:%S' >> ${DIR}/snaplog_${SID}.txt

cd ${CWD}
# Report SQL Ranking when snapshot level >= 5
/bin/date '+BEGIN SQLR %y/%m/%d %H:%M:%S' >> ${DIR}/snaplog_${SID}.txt

# if [ 5 -ge ${SNAPSHOT_LEVEL} ]; then
if [ ${SNAPSHOT_LEVEL} -ge 5 ]; then
	# Exec SQL Ranking report
	ORACMD="${CWD}/chcsv $USER -i ${CWD}/sqlrank.sql -o ${DIR}/sqlrank.txt ${OLD_ID} ${NEW_ID}"
	echo ${ORACMD} >> ${ERR}
#	${ORACMD} >> ${ERR} 2>&1
	# Exec SQL Ranking report(DEBUG)
	ORACMD="${CWD}/chcsv $USER -i ${CWD}/sqltop100_10g.sql -o ${DIR}/sqltop100_${SID}.txt ${OLD_ID} ${NEW_ID} ${OLD_ID} ${NEW_ID} ${OLD_ID} ${NEW_ID} ${OLD_ID} ${NEW_ID}"
	echo ${ORACMD} >> ${ERR}
	${ORACMD}  >> ${ERR} 2>&1
fi
/bin/date '+END   SQLR %y/%m/%d %H:%M:%S' >> ${DIR}/snaplog_${SID}.txt

/bin/date '+BEGIN OBJR %y/%m/%d %H:%M:%S' >> ${DIR}/snaplog_${SID}.txt
# Report Object Ranking when snapshot level >= 7
if [ ${SNAPSHOT_LEVEL} -ge 7 ]; then
        # Exec Object Ranking report
        ORACMD="${CWD}/chcsv $USER -i ${CWD}/objrank.sql -o ${DIR}/objrank_${SID}.txt ${OLD_ID} ${NEW_ID} ${OLD_ID} ${NEW_ID}"
	      echo ${ORACMD} >> ${ERR}
        ${ORACMD} >> ${ERR} 2>&1
fi
/bin/date '+END   OBJR %y/%m/%d %H:%M:%S' >> ${DIR}/snaplog_${SID}.txt

	}
else
	echo "No newest snapshot report."
	if [ "${OLD_ID}" -gt "${NEW_ID}" ]; then
		echo "STATSPACK SnapID was broken. Remove ${WORK}/snapids_${CATEGORY}_${SID}."
		rm ${WORK}/snapids_${CATEGORY}_${SID}
		exit 0
	fi
fi

# Purge snapshot
if [ 0 -lt $NSNAPID -a 0 -lt "${PURGE_LEVEL}" ]; then

	# Get oldest snap_id form Statspack
sqlplus $USER << EOF2 > $ERR 2>&1
spool ${WORK}/snapid.$$
select 'SNAPID '||min(snap_id) snap_id from stats\$snapshot;
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
sqlplus $USER << EOF3> $ERR 2>&1
define losnapid=${OLDEST_ID}
define hisnapid=${PURGE_ID}
@sppurge
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
