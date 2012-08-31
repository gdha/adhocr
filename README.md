# Ad-hoc Copy and Run (adhocr)

In large company environments they use a central directory systems to authenticate users against when users login onto a Linux/Unix or Windows box. Most likely the central directory service will be based on LDAP or Active Directory (of Microsoft). On the Unix boxes there is then a client install that communicates with this central directory service. It is mainly in such environments that *adhocr* is an useful and powerful tool.

# Introduction

This document provides guidance to the usage of the ad-hoc copy and run command (abbreviated as adhocr). Adhocr command was written on special request during the Storage HLM move to have a quick status of HBA's before and just after the move. Using a central controlled scheduling system was for these purposes not adequate as timing was of essence.
On occasions we were asked to write shell scripts to gather information on a bunch of systems, but the information is only needed during a short period of time, e.g. during a migration period. Writing and controlling this via a scheduling system may be overkill for these minor tasks, but still running these scripts on some systems may take too much time to be joyful. Well, for these kind of tasks adhocr may come to rescue as it was designed to be fast and simple to handle these collections, but still secure enough to pass rules around SOX compliancy and/or FDA regulation rules.


# Software Pre-Requisites

The adhocr command was written entirely in Korn Shell (and is 100% Bash compatible) shell and is therefore, rather portable on all UNIX systems that have either the Korn or Bash shell installed.
The adhocr command makes intensive use of the expect command and therefore, we need some additional software on the following Operating Systems to make adhocr functional:

- HP-UX 11.11, 11.23 or 11.31: use http://hpux.connect.org.uk/ to download the latest version of:
	* expect
	* tcltk
	* expat
	* fontconfig
	* freetype
	* gettext
	* libXft
	* libXrender
	* libiconv
	* zlib
	* You could also use '*depothelper*' tool to download and install all dependencies automagically.
- Linux (SLES 10.\*, SLES 11.\*, RHEL 4.\*, RHEL 5.\*, RHEL 6.*, Debian):
	* korn shell (ksh)
	* expect
	* tcltk


# Security Considerations

The adhocr command uses the Secure Shell or Secure Copy commands in the background in combination with the expect program to deal with the user interaction in a semi-automatic way. Therefore, the communication between the adhocr command the destination UNIX system is encrypted and passwords are never send in clear text. The user has to enter his/her password in the user.s own local pseudo-TTY, and the authentication is done with the regional Active Directory-domain server. Passwords are never visible on the screen and a double check has been build into adhocr program to scan on (own) passwords before storing the log files on disks.
The _root_ user is prohibited to execute (as root) the adhocr program to perform sudo-alike commands as _root_ is not part of the Unix engineers (_se_) group itself.

However, we would advise to limit the amount of servers where adhocr can run on to have a better way to control the (central) logging of the adhocr runs.

# Expect takes care of user interaction

When dealing with user interaction, such as entering passwords, then the normal UNIX shell fall short when for example we would like to run commands in the background. This limitation (user interaction) is as old as the UNIX operating system, but it was only in 1990 that an extension to the TCL language was written by Don Libes of NIST to deal with user interaction and that program was called `expect`.

# Adhocr usage

The best way to see what minimal required options are with the `adhocr` command is by running it without any option at all:

<pre>
$ adhocr

*************************************************
       adhocr : Ad-hoc Copy and Run
                version 1.4
*************************************************

Usage: adhocr [-p #max-processes] [-u username] [-k] -f filename-containing-systems [-h] -c "commands to execute"
        -p maximum number of concurrent processes running (in the background) [optional - default is 10]
        -u The user "username" should be part of the "se" group for executing sudo [default is gdha]
        -k keep the log directory with individual log files per system [optional - default is remove]
        -f filename containing list of systems to process
        -h show extended usage
        -c "command(s) to execute on remote systems"
</pre>

From above output we can tell that there are 2 required options, the `-f` option, which is a file containing fully qualified domain names of the systems we want to retrieve information of. And, the second required option is the `-c` option, which contains the command to execute on the remote systems.

And, a more extended usage is shown with the `-h` option:

<pre>
$ adhocr.sh -h

*************************************************
       adhocr : Ad-hoc Copy and Run
                version 1.4
*************************************************

Usage: adhocr.sh [-p #max-processes] [-u username] [-k] -f filename-containing-systems \
                [-l logging-directory] [-o output-directory] [-sudo] [-x|-nx] [-h] \
                [-up|-dl] [-t timeout secs] -c "commands to execute"

  -p #threads
         Maximum number of concurrent processes running (in the background)
        [optional - default is 10]
  -u <username>
         The user "username" should be part of the "se" group for executing sudo
        [optional - default is gdha]
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
</pre>

# Using adhocr as mass copy tool

We can use the adhocr command to copy files to many systems at once, e.g.

<pre>
$ adhocr -f ./yy -up -c  "/home/gdhaese/bin/daily_disk_scan.sh bin/"
</pre>

The above command (notice the `-up` option of upload) will copy the local file `/home/gdhaese/bin/daily_disk_scan.sh` to all the systems listed in file `./yy` to the remote location `bin/` of user $USER (yourself when `-u` option is not given).
Suppose in file yy we listed 800 systems then we better increase the limit of the maximum processes to run in parallel from the default 10 to something like 30 to speed up the copy process. Another handy option to change is the timeout (option `-t`), which is by default 900 seconds, to decrease this to something like 20 seconds.

To download use option `-dl`, is very similar, but in the command option `-c` we mention first the remote location of the file and then the local location.
For example to copy a script using expect and scp to all known HP-UX 11.11 based systems with a time-out of maximum 30 seconds and maximum 30 parallelized processes in the background:

<pre>
$ adhocr -p 30 -t 30 -f systems/HPUX1111-systems -up -c "/home/gdhaese/HPSIM/HPUX-Upgrade-RSP.sh  bin/"
</pre>

# Using adhocr to query simple things

We can use the adhocr command to retrieve simple information from a bunch of systems, e.g. the release of the Operating System:

<pre>
$ adhocr -f ./yy -c  "uname -r"
$ cat /home/HPL3usr/work/output/adhocr-2011-05-19.171419.output
BEGIN HOST ##### hpx189.company.com #####
spawn ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no gdhaese@hpx189.company.com uname -r
########################################################################
########################################################################

B.11.31
Execution time on host hpx189.company.com was 2 seconds
END HOST ##### hpx189.company.com #####
</pre>

