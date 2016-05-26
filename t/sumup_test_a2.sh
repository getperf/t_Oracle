#!/bin/bash
#
# Data aggrigation test script (ArrayFort)

LANG=C;export LANG
CWD=`dirname $0`
CMDNAME=`basename $0`

export SITEHOME="$(git rev-parse --show-toplevel)"

if [ ! -d "$SITEHOME/lib/Getperf/Command/Site" ]; then
	echo "Invalid site home directory '$SITEHOME'"
	exit -1
fi

# Create Linux domain for node config test
LINUX_DIR="$SITEHOME/analysis/test_a1/Linux"
if [ ! -d $LINUX_DIR ]; then
	mkdir -p $LINUX_DIR
fi

# Common aggrigation
sumup -t $SITEHOME/t/test_a1/Oracle/ora_seg__orcl.txt
sumup -t $SITEHOME/t/test_a1/Oracle/ora_tbs__orcl.txt
sumup -t $SITEHOME/t/test_a1/Oracle/spreport__orcl.lst

# For Statspack sql and object ranking
sumup -t $SITEHOME/t/test_a1/Oracle/ora_sql_top__orcl.lst
sumup -t $SITEHOME/t/test_a1/Oracle/ora_obj_top__orcl.lst

# For AWR aggrigation
# sumup -t $SITEHOME/t/test_a1/Oracle/awrreport__orcl.lst
# sumup -t $SITEHOME/t/test_a1/Oracle/awrreport_orcl.lst
# sumup -t $SITEHOME/t/test_a1/Oracle/ora_obj_topa__orcl.txt
# sumup -t $SITEHOME/t/test_a1/Oracle/ora_sql_topa__orcl.txt
