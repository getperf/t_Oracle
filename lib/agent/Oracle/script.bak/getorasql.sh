#!/bin/sh
#
# This procedure execute Oracle statspack snap and report.
#
# $STATCMD{'ORACLE'} = join ( "\n",
#        '_pwd_/getorasql.sh -i RTD -l _odir_ -u perfstat/perfstat -f oratab',
#        '_pwd_/getorasql.sh -i RTD -l _odir_ -u perfstat/perfstat -f orases -t 300 -c 36',

LANG=C;export LANG
COLUMNS=160;export COLUMNS
#resize -s 100 160
CMDNAME=`basename $0`
USAGE="Usage: $CMDNAME [-l dir] [-e errfile] [-i sid] [-u userid/passwd] [-f src] [-t interval] [-c cnt] [-x]"


# Set default param
CWD=`dirname $0`
DIR=.
SID=RTD
CNT=1
INTERVAL=10
USER=perfstat/perfstat
FILE=
ERR=/dev/null
CHECK_PROCESS=YES

# Get command option
OPT=
while getopts l:e:i:u:f:c:t:x OPT
do
        case $OPT in
        x)      CHECK_PROCESS="NO"
                ;;
        l)      DIR=$OPTARG
                ;;
        e)      ERR=$OPTARG
                ;;
        i)      SID=$OPTARG
                ;;
        u)      USERID=$OPTARG
                ;;
        f)      FILE=$OPTARG
                ;;
        c)      CNT=$OPTARG
                ;;
        t)      INTERVAL=$OPTARG
                ;;
        \?)     echo "$USAGE" 1>&2
                exit 1
                ;;
        esac
done
shift `expr $OPTIND - 1`

# Set current Date & Time
WORK="${CWD}/../_wk"

if [ ! -d ${WORK} ]; then
    /bin/mkdir -p ${WORK}
    if [ $? -ne 0 ]; then
        echo "Command failed."
        exit 1
    fi
fi

# --------- Oracle 環境変数設定 --------------
. ${CWD}/oracle_env

# Check Oracle process
if [ "YES" = "${CHECK_PROCESS}" ]; then
    ORACLE_SID=${SID}; export ORACLE_SID
    /bin/ps -ef | grep ora_smon_${SID} > ${WORK}/ora_ps.$$
    ORAPROC=`perl -ne 'print $1 if ($_=~/ora_smon_(.*)/ && $_!=~/grep/);' ${WORK}/ora_ps.$$` 
    /bin/rm -f ${WORK}/ora_ps.$$
    if [ "${ORACLE_SID}" != "${ORAPROC}" ]; then
        echo "ORACLE(${ORACLE_SID}) not found."
        exit 1
    fi
    /bin/rm -f ${WORK}/ora_ps.$$
fi

if [ ! -f "${CWD}/${FILE}.sql" ]; then
        echo "File not found."
        exit 1
fi

ORAFILE="${DIR}/${FILE}_${SID}.txt"
if [ -f $ORAFILE ]; then
        /bin/rm -f $ORAFILE
fi

ORASQL="${CWD}/${FILE}.sql"
ORACMD="${CWD}/chcsv $USERID -i ${ORASQL} -o ${WORK}/${FILE}.$$ > ${ERR} 2>&1"

ORACNT=1
while test ${ORACNT} -le ${CNT}
do
    # Sleep Interval
    if [ ${ORACNT} -ne ${CNT} ]; then
        sleep ${INTERVAL} &
    fi

    # Set Current Date
    /bin/date '+Date:%y/%m/%d %H:%M:%S' >> $ORAFILE

    # Exec ps command. 
    ${ORACMD} >> ${ERR}
    /bin/cat ${WORK}/${FILE}.$$ >> $ORAFILE
    wait
    ORACNT=`expr ${ORACNT} + 1`
done

/bin/rm ${WORK}/*.$$

exit 0
