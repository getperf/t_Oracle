#!/bin/sh
#
# This procedure execute Oracle statspack snap and report.
#

LANG=C;export LANG
COLUMNS=160;export COLUMNS
#resize -s 100 160
CMDNAME=`basename $0`
USAGE="Usage: \n  $CMDNAME [-s] [-n purgecnt] [-u user/pass@tns] [-c cat] [-i sid] [-l dir]\n"
USAGE="$USAGE           [-v snaplevel] [-e err] [-d script] [-x] [-t]"

# Set default param
CWD=`dirname $0`
MODE=
USER=perfstat/perfstat
PURGE=YES
PURGE_LEVEL=0
CATEGORY="ORACLE"
SCRIPT="ora10g"
SNAPSHOT_LEVEL=5
TBS_IO=NO
CHECK_PROCESS=YES

# Usage
# ./awrrep.sh -v 1 -d ora10g -l /tmp -i Y4VURA
# Oracle RAC Option
# If there are Oracle RAC Enviroment, this parameter should set 1 or 2 or ... with each node
INSTANCE_NUM=1		

DIR=.
SID=
ERR=

# Get command option
OPT=
while getopts tsn:c:l:i:v:e:u:d:x OPT
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
	t)	TBS_IO="YES"
		;;
	e)	ERR=$OPTARG
		;;
	d)	SCRIPT=$OPTARG
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

# Set ErrorLog
if [ "" = "${ERR}" ]; then
  ERR="${WORK}/stderr_spsum_${SID}_${CATEGORY}.txt"
fi

# --------- Oracle ä¬ã´ïœêîê›íË --------------
if [ ! -f ${CWD}/${SCRIPT}/oracle_env ]; then
	echo "File not fount: ${CWD}/${SCRIPT}/oracle_env"
	exit 1
fi
. ${CWD}/${SCRIPT}/oracle_env

SQLPLUS="${ORACLE_HOME}/bin/sqlplus"

if [ ! -x ${SQLPLUS} ]; then
	echo "File not fount: ${SQLPLUS}"
	exit 1
fi

CHCSV="${CWD}/${SCRIPT}/chcsv.sh"
if [ ! -x ${CHCSV} ]; then
	echo "File not fount: ${CHCSV}"
	exit 1
fi

# Check Oracle process
if [ "YES" = "${CHECK_PROCESS}" ]; then
	ORACLE_SID=${SID}; export ORACLE_SID
#	ORAPROC=`/bin/ps -ef | grep ora_smon_${SID} | perl -ne 'print \$1 if (\$_=~/ora_smon_(.*)/ && \$_!=~/grep/);'` 
#  if [ 0 != $? ]; then
#    echo "exec error : CHECK_PROCESS"
#    exit 1
#  fi
#
#	if [ "${ORACLE_SID}" != "${ORAPROC}" ]; then
#		echo "ORACLE(${ORACLE_SID}) not found."
#		exit 1
#	fi
	if [ "${SID}" = "STARYYY"  ]; then
		if [ ! -f "/starview/dat2/dbs/STARYYY/control01.ctl" ]; then
			echo "ORACLE(${ORACLE_SID}) not found."
			exit 0
		fi
	fi

	if [ "${SID}" = "RTDYYY" ]; then
		if [ ! -f "/rtd/dat2/dbs/RTDYYY/control01.ctl" ]; then
			echo "ORACLE(${ORACLE_SID}) not found."
			exit 0
		fi
	fi

	if [ "${SID}" = "URA0" ]; then
		if [ ! -f "/ura/dat3/dbs/URA0/controlURA001.ctl" ]; then
			echo "ORACLE(${ORACLE_SID}) not found."
			exit 0
		fi
	fi

	if [ "${SID}" = "YOKMST" ]; then
		if [ ! -f "/yokmst/dat1/dbs/YOKMST/control01.ctl" ]; then
			echo "ORACLE(${ORACLE_SID}) not found."
			exit 0
		fi
	fi

fi

# Get newest snap_id from Statspack
${SQLPLUS} -s ${USER} << EOF2 > ${ERR} 2>&1
set line 1000
WHENEVER SQLERROR EXIT 1;
spool ${WORK}/newid.$$
select 'R'||rownum||' '||SNAP_ID from
 (select SNAP_ID from DBA_HIST_SNAPSHOT 
  where SNAP_LEVEL = ${SNAPSHOT_LEVEL} 
  order by SNAP_ID desc) where rownum <= 2 ;
spool off
EOF2
if [ 0 != $? ]; then
  echo "ERROR[sqlplus] : select max(snap_id) from stats\$snapshot where INSTANCE_NUMBER=${INSTANCE_NUM};"
  cat $ERR
  exit 1
fi
perl -ne 'print $1 if /^R1\s*(\d*)/' ${WORK}/newid.$$ > ${WORK}/newid2.$$
perl -ne 'print $1 if /^R2\s*(\d*)/' ${WORK}/newid.$$ > ${WORK}/newid3.$$

if [ -f ${WORK}/newid2.$$ ]; then
	NEW_ID=`cat ${WORK}/newid2.$$`
else
	echo "newid not found."
	exit 1
fi
if [ -f ${WORK}/newid3.$$ ]; then
	OLD_ID=`cat ${WORK}/newid3.$$`
else
	echo "newid not found."
	exit 1
fi
/bin/rm -f ${WORK}/newid*.$$

echo "snap id : ${OLD_ID} - ${NEW_ID}"
# Report statspack
if [ 0 -lt "${NEW_ID}" -a "${OLD_ID}" -lt "${NEW_ID}" ]; then
{
cd ${CWD}/${SCRIPT}
${SQLPLUS} -s ${USER} << EOF > ${ERR} 2>&1
WHENEVER SQLERROR EXIT 1;
define report_type=text
define num_days=1
define begin_snap=${OLD_ID}
define end_snap=${NEW_ID}
define report_name=${DIR}/awrreport_${SID}
@awrrpt
EOF
if [ 0 != $? ]; then
  echo "ERROR[sqlplus] : ${CWD}/${SCRIPT}/awrrpt [${DIR}/awrreport_${SID}] [${OLD_ID}..${NEW_ID}]"
  cat $ERR
  exit 1
fi
}
else
	echo "No purge snapshot id."
fi

exit 0

