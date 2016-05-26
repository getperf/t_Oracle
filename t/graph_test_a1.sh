#!/bin/bash
#
# Graph creation test script (ArrayFort)

LANG=C;export LANG
CWD=`dirname $0`
CMDNAME=`basename $0`

export SITEHOME="$(git rev-parse --show-toplevel)"
if [ ! -d "$SITEHOME/node/Oracle/orcl" ]; then
	echo "Graph definition file is not found. Please run the data aggregation test in the beginning."
	exit -1
fi

cacti-cli -f $SITEHOME/node/Oracle/orcl

