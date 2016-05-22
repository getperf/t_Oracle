#!/bin/sh
#
# This procedure execute Oracle statspack snap and report.
#

LANG=C;export LANG
CMDNAME=`basename $0`
CWD=`dirname $0`
USAGE="Usage: $CMDNAME [dir]"

ODIR=$1

sh $CWD/getorasql.sh -i STARYYY   -l $ODIR -u starstate/starstate@STARYYY -f get_lotstat
sh $CWD/getorasql.sh -i STARYYY   -l $ODIR -u starstate/starstate@STARYYY -f get_lotwait
