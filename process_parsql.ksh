#!/bin/ksh
# DESCRIPTION
# Split SQL file to pieces and execute it in prarallel
# Usage: process_parsql.ksh -c commands_file [-d connect_string] [-p parallel_jobs] [-l log_dir]"
#   command_file is a file with a list of SQL commands one per line
#
#(YYYY/MM/DD)   MODIFIED
# 2012/07/24   Created - alexodba

usage="Usage: $0 -c commands_file  [-d connect_string] [-p parallel_jobs] [-l log_dir]\n 
Script run commands listed in commands_file in separate parallel tasks with pre-defined parallel degree.\n
By default:\n
  \tparallel_jobs - number of CPUs on server \n
  \tlog_dir - current directory \n "

while getopts c:p:l:d: name
do
        case $name in
        c) COMMFILE="$OPTARG";;
        p) PARALLEL="$OPTARG";;
        l) LOGDIR="$OPTARG";; 
        d) CONNSTR="$OPTARG";;
        ?) echo -e $usage
           exit 65;;
        esac
done

if [ -z "$COMMFILE"  ] ;
then 
        echo -e $usage
        exit 65
fi
if [ ! $COMMFILE ] ;
then
    echo "commands_file not found!"
    exit 65
fi

#log directory
if [ -z "$LOGDIR" ];
then 
  LOGDIR="/tmp"
fi

if [ -z "$CONNSTR" ];
then
  CONNSTR="/"
fi
COMMSPLIT="/tmp/`basename $COMMFILE`.$$"
trap 'rm -f ${COMMSPLIT}.* ; exit' 0 1 2 3 9 15
split -l 20 $COMMFILE $COMMSPLIT.

for f in ${COMMSPLIT}.* ; do  
  echo "set termout on echo on pages 0 lines 199 trimspo on" > $f.sql
  cat $f >> $f.sql
  echo "quit;
  /" >>$f.sql
  rm -f $f
done

ls -1 $COMMSPLIT.* | grep -v cmds | awk -v CONNSTR="$CONNSTR" '{print "sqlplus -L " CONNSTR " @"$1}' >  $COMMSPLIT.cmds

if [ -z "$PARALLEL" ] ;
then
  process_parall.ksh -c $COMMSPLIT.cmds -l $LOGDIR
else
  process_parall.ksh -c $COMMSPLIT.cmds -l $LOGDIR -p $PARALLEL
fi

LOGFILES=$LOGDIR/`basename $COMMSPLIT`.cmds*log
num_of_errors=`grep  ORA- $LOGFILES | wc -l`
if [ $num_of_errors -gt 0 ];
then
  grepora $LOGDIR/`basename $COMMSPLIT`.cmds*log
fi

exit $num_of_errors





