#!/bin/sh
#
# This procedure execute Oracle statspack snap and report.
#

LANG=C;export LANG
CMDNAME=`basename $0`
CWD=`dirname $0`
USAGE="Usage: $CMDNAME [dir]"

ODIR=$1

#sh $CWD/sprep.sh -s -i APC -u perfstat/perfstat@APC -r 1 -v 5 -d ora9i -x -l $ODIR
#sh $CWD/sprep.sh -s -i QDC -u perfstat/perfstat@QDC -r 2 -v 5 -d ora9i -x -l $ODIR
