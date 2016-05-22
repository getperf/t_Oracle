#!/bin/sh
#
# This procedure execute Oracle statspack snap and report.
#

LANG=C;export LANG
CMDNAME=`basename $0`
CWD=`dirname $0`
USAGE="Usage: $CMDNAME [dir]"

ODIR=$1

#sh -x $CWD/sprep2.sh -s -n 4 -c ORACLE_SUM -i APC  -u perfstat/perfstat@APC -r 1 -v 0 -d ora9i -x -l $ODIR
#sh -x $CWD/sprep2.sh -s -n 4 -c ORACLE_SUM -i QDC  -u perfstat/perfstat@QDC -r 2 -v 0 -d ora9i -x -l $ODIR
#sh $CWD/rebidx.sh -i APC  -u perfstat/perfstat@APC  -l $ODIR -b -x

sh -x $CWD/sprep2.sh -s -n 4 -c ORACLE_SUM -i APCT   -u perfstat/perfstat@APCT   -v 0 -d ora9i -x -l $ODIR
sh -x $CWD/sprep2.sh -s -n 4 -c ORACLE_SUM -i Y4APCT -u perfstat/perfstat@Y4APCT -v 0 -d ora9i -x -l $ODIR
sh $CWD/rebidx.sh -i APCT -u perfstat/perfstat@APCT -l $ODIR -b -x
