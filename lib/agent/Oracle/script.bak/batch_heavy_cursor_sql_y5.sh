#!/bin/sh
#
# This procedure execute Oracle statspack snap and report.
#

LANG=C;export LANG
CMDNAME=`basename $0`
CWD=`dirname $0`
USAGE="Usage: $CMDNAME [dir]"

ODIR=$1

sleep 30
sh $CWD/getorasql.sh -i STARYYY -l $ODIR -u perfstat/perfstat@STARYYY -f sga_util
sh $CWD/getorasql.sh -i RTDYYY  -l $ODIR -u perfstat/perfstat@RTDYYY  -f sga_util
sh $CWD/getorasql.sh -i URA0    -l $ODIR -u perfstat/perfstat@URA0    -f sga_util

sh $CWD/getorasql.sh -i STARYYY -l $ODIR -u perfstat/perfstat@STARYYY -f heavy_cursor_sql
sh $CWD/getorasql.sh -i RTDYYY  -l $ODIR -u perfstat/perfstat@RTDYYY  -f heavy_cursor_sql
sh $CWD/getorasql.sh -i URA0    -l $ODIR -u perfstat/perfstat@URA0    -f heavy_cursor_sql

