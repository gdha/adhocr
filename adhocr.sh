#!/usr/bin/ksh
# Author: Gratien D'haese
#
# ----------------------------------------------------------------------------
# adhocr = Ad-hoc copy and run script
# adhocr = ^^ ^^  ^        ^
# ----------------------------------------------------------------------------
# GOALS:
# =====
# * run commands in batch on remote Unix systems as a plain user with a central
#   point of logging and output (password could be required depending on
#   secure key authorization setup)
# * with the same script run commands as root with the help of sudo, but only
#   allow members of the se group to use sudo
# * be able to copy file to/from remote systems with logging
#
# Dependencies:
# ============
# HP-UX: 
# * install expect with the help of depothelper (all dependencies of expect
#	will automatically follow) 
#
# Linux: 
# * install expect with zypper or yum (all dependencies will automatically follow)


##############
# PARAMETERS #
##############
# The following 3 variables will be filled up through the Makefile (when used)
Version=1.4
CompanyName="Johnson & Johnson"
SudoGroup="se"

# start of local variables
PATH=/bin:/usr/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/contrib/bin
typeset -x PRGNAME=${0##*/}		# This script short name
typeset -x PRGDIR=${0%/*}		# This script directory name
typeset -x PASS				# password
typeset -i counter=0			# my HOST counter
HOST="UNDEFINED"
USER="$LOGNAME"				# default, user who executes this command
HERE=$(hostname)			# current hostname
OSname=$(uname -s)			# print the Operating System name, e.g. linux, HP-UX, SunOS
MARKER="#=-=-=#"			# if found in LOGFILE then generate a short (output) report
PTHREADS=10				# 10 parallel processes (default: use -p option modify)
DATE_TIME=$(date +'%Y-%m-%d.%H%M%S')	# format: 2011-03-31.155038
#
RUN_EXPECT=RunExpectSSH
RUN_EXPECT_SUDO=RunExpectSudo
RUN_EXPECT_SCP=RunExpectSCP
RUN_SSH=SecureShell
RUN_SCP=SecureCopy
EXPECT_SUDO=""				# default: None (is set to YES with -sudo)
SCP_FLOW=""				# default: None (use ssh instead)
ARGS=""					# arguments (will be filled a bit later)
KEEPLOGDIR=NO				# by default we will remove individual logfiles per system
#
NEED_PW=YES				# by default request user password
SCRIPT2RUN=$RUN_EXPECT			# defaul value for SCRIPT2RUN is run ssh (with expect) as yourself
SSHoptions="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"
GlobalConnectTimout=900			# 900 secs (to start with)
MASTER_PID=$$				# we need the master PID in case we want to kill the master process
TMP_FILENAME=/tmp/${PRGNAME}.$MASTER_PID	# temporary filename

[[ $PRGDIR = /* ]]  || PRGDIR=$(pwd)	# Acquire absolute path to the script

# ----------------------------------------------------------------------------
# F U N C T I O N S
# ----------------------------------------------------------------------------

function revision {
	typeset rev
	rev=$(awk '/Revision/ { print $3 }' $PRGDIR/$PRGNAME | head -1)
	[ -n "$rev" ] || rev="\"Under Development\""
	printf "%s" $rev
} # Acquire revision number of the script and plug it into the log file

function _ping {
	typeset i
	case $OSname in
		Linux|Darwin)
			i=`ping -c 2 ${1} | grep "packet loss" | cut -d, -f3 | awk '{print $1}' | cut -d% -f1 | cut -d. -f1`
			;;
		HP-UX|CYGWIN_NT-5.1)
			i=`ping ${1} -n 2 | grep "packet loss" | cut -d, -f3 | awk '{print $1}' | cut -d% -f1 | cut -d. -f1`
			;;
		SunOS)
			i=`ping ${1} >/dev/null 2>&2; echo $?`
			;;
	esac
	[ -z "$i" ] && i=2	# when ping returns "host unknown error"
	echo $i
}

function Timeout_hanging_jobs {
	typeset -i _elapsetime=0
	ps -ef | grep $USER | egrep '(ssh|scp)' | grep Conn | awk '{print $2, $5}' | while read _pid _starttime
	do
		_elapsetime=$(($(date '+%H:%M:%S' | awk -F':' '{print $1*3600 + $2*60 + $3 }')-$(echo $_starttime | awk -F':' '{print $1*3600 + $2*60 + $3 }')))
		if [ $_elapsetime -gt $GlobalConnectTimout ]; then
			KillHangingJobs $_pid
		fi
	done
}

function Timeout_hanging_jobs_when_finished {
	typeset -i timeout=0			# my internal timeout counter
	while [ $timeout -lt $GlobalConnectTimout ]
	do
		jobcount=$(jobs | grep -v Done | wc -l)
		if (( jobcount == 0 )) ; then
			break
		else
			echo "      - $jobcount running jobs at this moment." | tee -a $LOGFILE
			sleep 10
		fi
		timeout=$((timeout+10))
	done
	if [ $(jobs | grep -v Done | wc -l) -ge 1 ]; then
		echo "The GlobalConnectTimout has been reached ($GlobalConnectTimout)" | tee -a $LOGFILE
		echo "Perhaps the following jobs are hanging :" | tee -a $LOGFILE
		jobs | grep -v Done | tee -a $LOGFILE
		ps -ef | grep $USER | egrep '(ssh|scp)' | grep Conn | tee -a $LOGFILE
		KillHangingJobs $(ps -ef | grep $USER | egrep '(ssh|scp)' | grep Conn | awk '{print $2}')
	fi
}

function KillHangingJobs {
	# input: list of PIDs to kill (hanging jobs)
	[ -z "$@" ] && return
	for pid in "$@"
	do
		ps -e | grep -q $pid && kill -9 $pid | tee -a $LOGFILE
	done
}

function is_var_empty {
	if [ -z "$1" ]; then
		showusage
		exit 1
	fi
}

function isnum {
	echo $(($1+0))		# returns 0 for non-numeric input, otherwise input=output
}

function TimeSpend {
	# here we will calculate the time spend for each job we start
	# $LOGDIR/$DATE_TIME/.time.$HOST will contain the time in seconds
	echo "$((SECONDS-starttime))" > $LOGDIR/$DATE_TIME/.time.$HOST
}

function _echo {
	case $OSname in
		Linux|Darwin) arg="-e " ;;
	esac
	echo $arg "$*"
} # echo is not the same between UNIX and Linux

function _line {
	typeset -i i
	while (( i < ${1:-80} )); do
		(( i+=1 ))
		_echo "-\c"
	done
	echo
} # draw a line

function GenerateOutputFile {

	echo
	echo "*** Logfile = $LOGFILE (containing error messages)" | tee -a $LOGFILE
	echo "*** Output  = $OUTPUTFILE (concatenated output of system output)" | tee -a $LOGFILE

	( for HOST in `cat $TMP_FILENAME`; do

		# print a marker . to the screen to show that there is some work in progress
		case $OSname in
			Linux|Darwin|CYGWIN_NT-5.1) echo -n "." ;;
			HP-UX|SunOS) echo ".\c" ;;
		esac

		[ ! -f $LOGDIR/$DATE_TIME/$HOST ] && continue
		echo "BEGIN HOST ##### $HOST #####" >> $OUTPUTFILE
		grep -q "$MARKER" $LOGDIR/$DATE_TIME/$HOST
		if [ $? -eq 0 ]; then

			awk '/#=-=-=#Start/,/#=-=-=#End/ {if ($0 !~ "#=-=-=#Start" && $0 !~ "#=-=-=#End") print}' $LOGDIR/$DATE_TIME/$HOST >>$OUTPUTFILE

		else

			# remove the banner from the output
			cat $LOGDIR/$DATE_TIME/$HOST | grep -v  "^#  " | grep -v  "^#############" >> $OUTPUTFILE

		fi

		AnalyseErrorMessages >> $OUTPUTFILE

		if [ -f $LOGDIR/$DATE_TIME/.time.$HOST ]; then
			echo "Execution time on host $HOST was $(cat $LOGDIR/$DATE_TIME/.time.$HOST) seconds" >> $OUTPUTFILE
		fi

		echo "END HOST ##### $HOST #####" >> $OUTPUTFILE
		_line >> $OUTPUTFILE		# draw a line after each host

	done 2>&1 )

	echo	# to have a C/R after the last . on the screen
	if [ "$KEEPLOGDIR" = "YES" ]; then
		echo "*** Output directory = $LOGDIR/$DATE_TIME/" | tee -a $LOGFILE
	else
		echo "*** Removing Output directory $LOGDIR/$DATE_TIME/" | tee -a $LOGFILE
		rm -rf $LOGDIR/$DATE_TIME/
	fi

	# counting errors in output file
	err=$(grep -wc '::Error::' $OUTPUTFILE)
	if [ $err -gt 0 ]; then
		_line | tee -a $LOGFILE $OUTPUTFILE
		echo "Found $err error(s) in the $OUTPUTFILE file." | tee -a $LOGFILE $OUTPUTFILE
		grep '::Error::' $OUTPUTFILE | tee -a $LOGFILE $OUTPUTFILE
		echo "Please investigate..." | tee -a $LOGFILE $OUTPUTFILE
		_line | tee -a $LOGFILE $OUTPUTFILE
	fi
}

function ShowBanner {
echo "
*************************************************
       adhocr : Ad-hoc Copy and Run
                version $Version
*************************************************
" | tee -a $LOGFILE
}

function showusage {
	echo "Usage: $PRGNAME [-p #max-processes] [-u username] [-k] -f filename-containing-systems [-h] -c \"commands to execute\""
	echo "	-p maximum number of concurrent processes running (in the background) [optional - default is 10]"
	echo "	-u The user \"username\" should be part of the \"${SudoGroup}\" group for executing sudo [default is $USER]"
	echo "	-k keep the log directory with individual log files per system [optional - default is remove]"
	echo "	-f filename containing list of systems to process"
	echo "	-h show extended usage"
	echo "	-c \"command(s) to execute on remote systems\""
}

function show_extended_usage {
	cat - <<end-of-text
Usage: $PRGNAME [-p #max-processes] [-u username] [-k] -f filename-containing-systems \\
		[-l logging-directory] [-o output-directory] [-sudo] [-x|-nx] [-h] \\
		[-up|-dl] [-t timeout secs] -c "commands to execute"

  -p #threads
	 Maximum number of concurrent processes running (in the background)
	[optional - default is 10]
  -u <username>
	 The user <username> should be part of the "${SudoGroup}" group for executing sudo
	[optional - default is $USER]
  -k
	keep the log directory with individual log files per system
	[optional - default is remove]
  -f <filename>
	Filename containing list of systems to process [required]
  -l <logdir>
	Directory to keep the logs
	[optional - default ~/logs]
  -o <outputdir>
	Directory to store output
	[optional - default ~/output]
  -sudo
	Force remote commands to be executed via sudo
	[optional - default NO]
  -x|-expect
	Use expect to login remotely (e.g. no SSH keys were exchanged)
	[optional - default YES]
  -npw|-nx|-bg
	Use only SSH (without expect) to execute remote commands
	[optional - default NO]
  -up
	Upload documents with scp (with expect -x or without expect -nx)
	[optional - default NO]
	The scp default is to upload documents (use -dl to download documents)
  -dl
	Download documents with scp (default with expect, use -nx to use scp only)
  -t <seconds>
	timeout in seconds [optional - default 900]
  -h
	Show extended usage (this screen)
  -c <command(s)>
	Commands to execute on remote system(s), e.g. "uname -r" [required]
	Note 1: upload copy (-up) commands are "local-file remote-file"
	Note 2: download copy (-dl) commands are "remote-file local-file"
end-of-text
}

function show_sudo_banner {
	cat - <<-end-of-text
################################################################################
                          S U D O     W A R N I N G
################################################################################
 You are about to be granted root shell access. By continuing, you agree to
 the following requirements:

   - Your access to the root shell must have been authorized by being a member
     of one of the groups that grants this access.
   - You may not use the privileges granted by the use of the root shell to
     grant elevated privileges to any other user or any other account.
   - If you have been granted root shell access on a temporary basis, you MUST
     exit the root shell as soon as you complete your actions.

 Unauthorized use may subject you to ${CompanyName} disciplinary proceedings
 and/or criminal and civil penalties under state, federal or other applicable
 domestic and foreign laws. The use of this system may be monitored and recorded
 for administrative and security reasons. If such monitoring and/or recording
 reveal possible evidence of criminal activity, ${CompanyName} may provide
 the evidence of such monitoring to law enforcement officials.
################################################################################
end-of-text
}

function check_user_part_of_se_group {
	groups $1 2>/dev/null | awk -v RS=" " 'BEGIN {found=1} ($1 == "${SudoGroup}") {found=0} END {print found}'
}

function Prompt_User_for_Password {
	echo "  ** Enter the ${CompanyName} password of user $USER:"
	stty -echo
	read PASS
	stty echo
}

function Error {
        echo "ERROR: $*" | tee -a $LOGFILE
        kill $MASTER_PID # make sure that Error exits the master process, even if called from child processes :-)
}

function ExitHangingJobs {
	# when running with -nx option (only use SSH without expect then it can happen that certain
	# batch jobs are hanging because there waiting on a password)
	# By pressing Ctrl-C we can interrupt these processes and continue with the main script
	# However, we still want to have the output file
	KillHangingJobs $(ps -ef | grep $USER | egrep '(ssh|scp)' | grep Conn | awk '{print $2}')
	GenerateOutputFile
	trap "" HUP INT QUIT TERM
	exit 0
}

function FindString {
	grep -i "$1" $LOGDIR/$DATE_TIME/$HOST >/dev/null 2>&1
	return $?
}

function AnalyseErrorMessages {
	# purpose of function is trace trivial error messages in log file (per host)
	# and report this in output file (append)
	typeset -i i=0
	FindString "permission denied" && \
		echo "::Error:: permission denied for user $USER on host $HOST"
	FindString "connection refused" && \
		echo "::Error:: ssh connection refused for user $USER on host $HOST"
	FindString "no such file or directory" && \
		echo "::Error:: no such file or directory on host $HOST"
	FindString "usage: scp" && \
		echo "::Error:: Usage: scp missing arguments on host $HOST"
	FindString "connection timed out" && \
		echo "::Error:: ssh connection timed out on host $HOST"
	FindString "connection closed" && \
		echo "::Error:: ssh connection closed on host $HOST"
	FindString "Killed by signal 15" && \
		echo "::Error:: timeout exceeded on host $HOST (perhaps increase timeout ${GlobalConnectTimout}?)"
}

function SecureShell {
	# input args: $USER $HOST $CMD
	echo "======= $HOST (starting at $(date +%m%d%y_%H%M))" | tee -a $LOGFILE
	starttime=$SECONDS
	ssh $SSHoptions -o PasswordAuthentication=no $1@$2 $3 >$LOGDIR/$DATE_TIME/$2 2>&1
	echo "======= $HOST (ending at $(date +%m%d%y_%H%M))" | tee -a $LOGFILE
	TimeSpend
}

function SecureCopy {
	USER=$1
	HOST=$2
	CMD=$3
	echo "======= $HOST (starting at $(date +%m%d%y_%H%M))" | tee -a $LOGFILE
	starttime=$SECONDS
	if [ "$SCP_FLOW" = "UPLOAD" ]; then
		LF=$(echo $CMD | awk '{print $1}')
		RF=$(echo $CMD | awk '{print $2}')
		[ -z "$LF" ] && Error "scp: command argument [-c] needs minimum a local filename"
		scp $SSHoptions -p -o PasswordAuthentication=no $LF $USER@$HOST:$RF >$LOGDIR/$DATE_TIME/$HOST 2>&1
	elif [ "$SCP_FLOW" = "DOWNLOAD" ]; then
		LF=$(echo $CMD | awk '{print $2}')
		RF=$(echo $CMD | awk '{print $1}')
		[ -z "$RF" ] && Error "scp: command argument [-c] needs minimum a remote filename"
		[ -z "$LF" ] && LF="."
		scp $SSHoptions -p -o PasswordAuthentication=no $USER@$HOST:$RF $LF >$LOGDIR/$DATE_TIME/$HOST 2>&1
	else
		Error "use -up (UPLOAD) or -dl (DOWNLOAD) to copy files to $HOST"
		LF=""
		RF=""
	fi
	echo "======= $HOST (ending at $(date +%m%d%y_%H%M))" | tee -a $LOGFILE
	TimeSpend
}

function RunExpectSSH {
	echo "======= $HOST (starting at $(date +%m%d%y_%H%M))" | tee -a $LOGFILE
	starttime=$SECONDS
	USER=$1
	HOST=$2
	CMD=$3
	# input args: $USER $HOST
	VAR=$(expect -c "
	set password \$env("PASS") ;
	spawn ssh $SSHoptions $USER@$HOST  $CMD
	match_max 100000 ;
	set timeout 10 ;
	expect  {
		\"(yes/no)?\" { send -- \"yes\\r\" } ;
		\"*?assword:*\" {
			send -- \"\$password\\r\" ;
			expect -re \"\[\$@#>] $\" ;
			}
	}

	#send -- \"\\r\" ;
	#expect -re \"\[\$@#>] $\" ;

	#send -- \"$CMD\\r\" ;
	#expect -re \"\[\$@#>] $\" ;
	#send -- \"exit\\r\" ;
	#expect eof ;
	wait
	")	# end-of-expect VAR

	echo "$VAR" >$LOGDIR/$DATE_TIME/$2 2>&1
	echo "======= $HOST (ending at $(date +%m%d%y_%H%M))" | tee -a $LOGFILE
	TimeSpend
}

function RunExpectSCP {
	echo "======= $HOST (starting at $(date +%m%d%y_%H%M))" | tee -a $LOGFILE
	starttime=$SECONDS
	USER=$1
	HOST=$2
	# CMD: should be local-file remote-file (with upload), or
	#       remote-file local-file (with download)
	CMD=$3
	if [ "$SCP_FLOW" = "UPLOAD" ]; then
		LF=$(echo $CMD | awk '{print $1}')
		RF=$(echo $CMD | awk '{print $2}')
		[ -z "$LF" ] && Error "scp: command argument [-c] needs minimum a local filename"
		VAR=$(expect -c "
			set password \$env("PASS") ;
			spawn scp $SSHoptions -p $LF $USER@$HOST:$RF
			match_max 100000 ;
			set timeout 10 ;
			expect  {
				\"(yes/no)?\" { send -- \"yes\\r\" } ;
				\"*?assword:*\" {
					send -- \"\$password\\r\" ;
					expect -re \"\[\$@#>] $\" ;
					}
				}
			")      # end-of-expect VAR
	elif [ "$SCP_FLOW" = "DOWNLOAD" ]; then
		LF=$(echo $CMD | awk '{print $2}')
		RF=$(echo $CMD | awk '{print $1}')
		[ -z "$RF" ] && Error "scp: command argument [-c] needs minimum a remote filename"
		[ -z "$LF" ] && LF="."
		VAR=$(expect -c "
			set password \$env("PASS") ;
			spawn scp $SSHoptions -p $USER@$HOST:$RF $LF
			match_max 100000 ;
			set timeout 10 ;
			expect  {
				\"(yes/no)?\" { send -- \"yes\\r\" } ;
				\"*?assword:*\" {
					send -- \"\$password\\r\" ;
					expect -re \"\[\$@#>] $\" ;
					}
				}
			")      # end-of-expect VAR
	else
		Error "use -up (UPLOAD) or -dl (DOWNLOAD) to copy files to $HOST"
		LF=""
		RF=""
	fi
	echo "$VAR" >$LOGDIR/$DATE_TIME/$2 2>&1
	echo "======= $HOST (ending at $(date +%m%d%y_%H%M))" | tee -a $LOGFILE
	TimeSpend
}


function RunExpectSudo {
	echo "======= $HOST (starting at $(date +%m%d%y_%H%M))" | tee -a $LOGFILE
	starttime=$SECONDS
	# Variable VAR contains the expect section
	USER=$1
	HOST=$2
	CMD=$3
	VAR=$(expect -c "
	proc do_exit {msg} {
		puts stderr $msg
		exit 1
	}

	set password \$env("PASS") ;


	spawn ssh $SSHoptions $USER@$HOST

	match_max 100000
	set timeout 8
	expect  {
		\"(yes/no)?\" { send -- \"yes\\r\" }
		\"*?assword:*\" {
			send -- \"\$password\\r\" ;
			# continue looping in this 'expect' block until the 'prompt' is reached
			expect -re \"\[\$@#>] $\" ;
			exp_continue
			}
		expect -re \"\[\$@#>] $\"
	}

	#set timeout 5 
	#expect  {
	#	\"*?assword:*\" {
	#		send -- \"\$password\\r\" ;
	#		expect -re \"\[\$@#:>](.*)\" ;
	#		##expect -re \"\[\$@#>] $\" ;
	#		}
	#}
	send -- \"\\r\" ;	# send an additional CR before sending a real CMD (sometimes profile ask for a CR)
	expect -re \"\[\$@#:>](.*)\" ;
	##expect -re \"\[\$@#>] $\" ;

	send \"sudo su -\\r\" ;
	sleep 1 ;
	set timeout 8 ;
	expect {
		\"*?assword:*\" {
			send -- \"\$password\\r\" ;
			###expect -re \"\[\$@#:>] $\" ;
			expect -re \"\[\$@#:>](.*)\" ;
			}
	}	
	set timeout 5 ;
	send -- \"\\r\" ;	# send an additional CR before sending a real CMD (sometimes profile ask for a CR)
	expect -re \"\[\$@#:>](.*)\" ;
	set timeout 4500 ;	# set timeout to 75 min (for slower systems or with plenty of disks)
	send -- \"$CMD\\r\" ;
	expect -re \"\[\$@#:>](.*)\" ;
	send -- \"exit\\r\" ;
	expect -re \"\[\$@#:>](.*)\" ;
	send -- \"exit\\r\" ;
	expect eof ;
	")	# END of inspect section (variable VAR)

	# now execute VAR and log the output in directory structure per system
	echo "$VAR"  >$LOGDIR/$DATE_TIME/$HOST 2>&1

	echo "======= $HOST (ending at $(date +%m%d%y_%H%M))" | tee -a $LOGFILE
	TimeSpend
}
function Cleanup {
	# clean up
	rm -f $TMP_FILENAME
}

# ----------------------------------------------------------------------------
#			 =========== M A I N ============
# ----------------------------------------------------------------------------

ShowBanner

if [ "$#" = "0" ]; then
	showusage
	exit 1
fi

# Process any command-line options that are specified
while [ $# -gt 0 ]
do
	case $1 in

		-p )
			PTHREADS="$2"
			is_var_empty "$PTHREADS"
			PTHREADS=$(isnum $PTHREADS)
			[ $PTHREADS -eq 0 ] && PTHREADS=10
			shift 2 ;;

		-f )
			FILENAME="$2"
			is_var_empty "$FILENAME"
			if [ ! -f $FILENAME ]; then
				echo "Expecting a filename with the -f option!"
				showusage
				exit 1
			fi
			shift 2 ;;

		-u )
			USER="$2"
			is_var_empty "$USER"
			shift 2 ;;

		-c )
			CMD="$2"
			is_var_empty "$CMD"
			shift 2 ;;

		-k )
			KEEPLOGDIR=YES
			shift 1 ;;

		-l )
			# LOGDIR location (overrides default $(pwd)/logs)
			LOGDIR="$2"
			is_var_empty "$LOGDIR"
			if [ ! -d $LOGDIR ]; then
				showusage
				exit 1
			fi 
			shift 2 ;;

		-o )
			# OUTDIR location (overrides default $(pwd)/output)
			OUTDIR="$2"
			is_var_empty "$OUTDIR"
			if [ ! -d $OUTDIR ]; then
				showusage
				exit 1
			fi
			shift 2 ;;

		-sudo )
			NEED_PW=YES
			EXPECT_SUDO=YES
			SCRIPT2RUN="$RUN_EXPECT_SUDO"
			shift 1 ;;

		-x | -expect )
			NEED_PW=YES
			SCRIPT2RUN="$RUN_EXPECT"
			shift 1 ;;

		-npw | -nx | -bg )
			NEED_PW=NO
			FORCE_NO_PW=YES
			##SCRIPT2RUN="$RUN_SSH" or "$RUN_SCP" (depends on SCP_FLOW)
			shift 1 ;;

		-up )
			NEED_PW=YES
			SCRIPT2RUN="$RUN_EXPECT_SCP"
			SCP_FLOW=UPLOAD
			shift 1 ;;

		-dl )
			NEED_PW=YES
			SCRIPT2RUN="$RUN_EXPECT_SCP"
			SCP_FLOW=DOWNLOAD
			shift 1 ;;

		-t )
			GlobalConnectTimout="$2"
			is_var_empty "GlobalConnectTimout"
			GlobalConnectTimout=$(isnum $GlobalConnectTimout)
			[ $GlobalConnectTimout -eq 0 ] && GlobalConnectTimout=900
			shift 2 ;;

		-h )
			show_extended_usage
			shift 1
			exit 1 ;;

		* )
			showusage
			exit 1 ;;

	esac
			
done

# Some pre-processing steps after processing the parameters from cmd line:
###########################################################################
[ -z "$LOGDIR" ] && LOGDIR=$(pwd)/logs			# always nice to have the logs in a seperate dir
[ ! -d $LOGDIR ] && LOGDIR="."				# check if a logs dir exists, if not use $PWD
[ ! -d $LOGDIR/$DATE_TIME ] && mkdir -m 755 $LOGDIR/$DATE_TIME
LOGFILE="${LOGDIR}/$(basename $0)-${DATE_TIME}.log"

[ -z "$OUTDIR" ] && OUTDIR=$(pwd)/output
[ ! -d $OUTDIR ] && OUTDIR="."
##[ ! -d $OUTDIR/$DATE_TIME ] && mkdir -m 755 $OUTDIR/$DATE_TIME
OUTPUTFILE="$OUTDIR/$(basename $0)-${DATE_TIME}.output"

# basic check: do we have a FILENAME?
if [ -z "$FILENAME" ]; then
	echo "Expecting a filename with the -f option!"
	showusage
	exit 1
fi

# if "-x" and "-sudo" were both set then -sudo will win
if [ "$EXPECT_SUDO" = "YES" ]; then
	SCRIPT2RUN="$RUN_EXPECT_SUDO"
	NEED_PW=YES					# make sure pw is needed (even when -nx was an option)
	FORCE_NO_PW=NO					# make sure pw is needed (even when -nx was an option)
fi

[ "$FORCE_NO_PW" = "YES" ] && NEED_PW=NO		# -npw (or -nx or -bg option set)

# The -x and -sudo require a password of USER
if [ "$NEED_PW" = "YES" ]; then
	if [ "$EXPECT_SUDO" = "YES" ]; then
		if [ $(check_user_part_of_se_group "$USER") -ne 0 ]; then
			echo "::Error:: User $USER not part of \"${Sudogroup}\" group, and therefore, sudo is not allowed."
			exit 1
		fi
		show_sudo_banner
	fi
	Prompt_User_for_Password
else
	if [ "$SCP_FLOW" = "UPLOAD" ]; then
		SCRIPT2RUN="$RUN_SCP"           # -up (and -nx (or -bg or -npw))
	elif [ "$SCP_FLOW" = "DOWNLOAD" ]; then
		SCRIPT2RUN="$RUN_SCP"           # -dl (and -nx (or -bg or -npw))
	else
		# default is empty string for SCP_FLOW
		SCRIPT2RUN="$RUN_SSH"           # -nx (or -bg or -npw)
	fi
fi

# define the trap statement after the password prompt, otherwise it will try
# to run the "ExitHangingJobs" function anyway (and that is not what we want!)
trap "ExitHangingJobs" HUP INT QUIT TERM

# first remove comment lines and/or empty line from FILENAME
cat $FILENAME | sed -e 's/^#.*//' -e 's/#.*//' | grep -v '^$' > $TMP_FILENAME
# The FILENAME contains list of systems to process (one per line) and could be very long
# We will split the files in pieces acording the $PTHREADS variable
_Amount_Systems=$(cat $TMP_FILENAME | wc -l)

# ARGUMENTS are:
ARGS="-u $USER -k -l $LOGDIR -d $DATE_TIME -o $OUTDIR -p $PTHREADS"


####################################
## Show parameters before starting #
####################################
echo "Script name : $0" | tee -a $LOGFILE
echo "Filename containing list of systems : $FILENAME" | tee -a $LOGFILE
echo "Amount of systems to roll-over is $_Amount_Systems" | tee -a $LOGFILE
echo "Will execute the commands in a bunch of $PTHREADS" | tee -a $LOGFILE
echo "Command to execute : $CMD" | tee -a $LOGFILE
if [ "$KEEPLOGDIR" = "YES" ]; then
	echo "We will keep the individual log files found under $LOGDIR/$DATE_TIME" | tee -a $LOGFILE
else
	echo "The individual log files found under $LOGDIR/$DATE_TIME will be removed at the end" | tee -a $LOGFILE
fi
echo | tee -a $LOGFILE

( for HOST in `cat $TMP_FILENAME`; do

#echo "===============" | tee -a $LOGFILE

x=$(_ping $HOST)
if [ $x -eq 1 ]; then
	echo "::Error:: Host $HOST not reachable from $HERE" | tee -a $LOGFILE $LOGDIR/$DATE_TIME/$HOST
elif [ $x -eq 2 ]; then
	echo "::Error:: Host $HOST unknown" | tee -a $LOGFILE $LOGDIR/$DATE_TIME/$HOST
else
	counter=$((counter+1))
	case "$SCRIPT2RUN" in

		"$RUN_SSH" )
			echo "[$counter] Executing ssh $USER@$HOST $CMD" | tee -a $LOGFILE
			SecureShell $USER $HOST "$CMD" &
			;;

		"$RUN_EXPECT" )
			echo "[$counter] Executing expect with ssh $USER@$HOST $CMD" | tee -a $LOGFILE 
			RunExpectSSH $USER $HOST "$CMD" &
			;;

		"$RUN_EXPECT_SUDO" )
			echo "[$counter] Executing expect (and sudo) with ssh $USER@$HOST $CMD" | tee -a $LOGFILE
			RunExpectSudo $USER $HOST "$CMD" &
			;;

		"$RUN_EXPECT_SCP" )
			echo "[$counter] Executing expect with scp $USER@$HOST $CMD" | tee -a $LOGFILE
			RunExpectSCP $USER $HOST "$CMD" &
			;;

		"$RUN_SCP" )
			echo "[$counter] Executing scp $USER@$HOST $CMD" | tee -a $LOGFILE
			SecureCopy $USER $HOST "$CMD" &
			;;

	esac
	while [ $(jobs | wc -l) -ge $PTHREADS ]
	do
		sleep 2
		Timeout_hanging_jobs
	done
fi
done 2>&1
Timeout_hanging_jobs_when_finished
wait
)


############## Re-assemble the logs in one big output file ###############
GenerateOutputFile
Cleanup
trap "" HUP INT QUIT TERM
exit 0
# ----------------------------------------------------------------------------
