#!/bin/ksh
# DESCRIPTION
# Run set of commands in parallel
# Usage: process_parall.sh -c commands_file [-p parallel_jobs] [-l log_dir]"
#   command_file is a files with a list of commands one per line
#
#(YYYY/MM/DD)   MODIFIED
# 2007/06/13  Create - alexodba
# 2011/0729   Adopted to ksh  - alexodba

#set -x
MAKE=gmake
#parse command line
usage="Usage: $0 -c commands_file [-p parallel_jobs] [-l log_dir]\n 
Script run commands listed in commands_file in separate parallel tasks with pre-defined parallel degree.\n
By default:\n
  \tparallel_jobs - number of CPUs on server \n
  \tlog_dir - current directory \n\n "
trap 'rm -f ${MAKEFILE} ; exit' 0 1 2 3 9 15
#set -f #enable globbing
#set x `getopt c:p:l: $*`

while getopts c:p:l: name
do
        case $name in
        c) COMMFILE="$OPTARG";;
        p) PARALLEL="$OPTARG";;
        l) LOGDIR="$OPTARG";; 
        ?) echo $usage
           exit 65;;
        esac
done

if [ -z "$COMMFILE" ] ;
then 
        echo  -e $usage
        exit 65
fi
# number of jobs to run in parallel
if [ -z "$PARALLEL" ];
then 
#  PARALLEL=4
#By default is a CPU count
  if [ "`uname`" = "HP-UX" ]
  then
    let PARALLEL="`ioscan -kC processor |grep -c processor`"
  else  
    let PARALLEL="`mpstat -P ALL | wc -l` - 4"
  fi
fi

#log directory
if [ -z "$LOGDIR" ];
then 
  LOGDIR="`pwd`"
fi

#set initial values for variables
export PROCPREF=$$
export MAKEFILE="MakeFile.`date '+%Y%m%d%H%M%S'`.$RANDOM.$PROCPREF"
#export MAKEFILE=m
rm -f $MAKEFILE
touch $MAKEFILE

TASKNUM=0
ALLTASKS="all:"
echo "SHELL=/usr/bin/ksh"  >> $MAKEFILE
while read comm
do
  LOG="`basename ${COMMFILE}``echo ${comm} | tr -d '[:blank:][:punct:][:cntrl:][:space:]'`"
  echo "task${TASKNUM}:" >> $MAKEFILE
  echo "	@echo Runing ${comm}" >> $MAKEFILE
  echo "	@${comm} 1>${LOGDIR}"/"${LOG}.`date '+%Y%m%d%H%M%S'`.$RANDOM.$PROCPREF.log 2>&1" >> $MAKEFILE
  echo "	@echo Finished ${comm}" >> $MAKEFILE
  ALLTASKS="$ALLTASKS task$TASKNUM"
  let "TASKNUM += 1"
done < $COMMFILE

echo "$ALLTASKS" >> $MAKEFILE
$MAKE all -f $MAKEFILE -j $PARALLEL -i





