#!/bin/sh
#
# Log file pattern detector plugin for Nagios
# Written by Ethan Galstad (nagios@nagios.org)
# Last Modified: 07-31-1999
#
# Usage: ./check_log <log_file> <old_log_file> <pattern>
#
# Description:
#
# This plugin will scan a log file (specified by the <log_file> option)
# for a specific pattern (specified by the <pattern> option).  Successive
# calls to the plugin script will only report *new* pattern matches in the
# log file, since an copy of the log file from the previous run is saved
# to <old_log_file>.
#
# Output:
#
# On the first run of the plugin, it will return an OK state with a message
# of "Log check data initialized".  On successive runs, it will return an OK
# state if *no* pattern matches have been found in the *difference* between the
# log file and the older copy of the log file.  If the plugin detects any 
# pattern matches in the log diff, it will return a CRITICAL state and print
# out a message is the following format: "(x) last_match", where "x" is the
# total number of pattern matches found in the file and "last_match" is the
# last entry in the log file which matches the pattern.
#
# Notes:
#
# If you use this plugin make sure to keep the following in mind:
#
#    1.  The "max_attempts" value for the service should be 1, as this
#        will prevent Nagios from retrying the service check (the
#        next time the check is run it will not produce the same results).
#
#    2.  The "notify_recovery" value for the service should be 0, so that
#        Nagios does not notify you of "recoveries" for the check.  Since
#        pattern matches in the log file will only be reported once and not
#        the next time, there will always be "recoveries" for the service, even
#        though recoveries really don't apply to this type of check.
#
#    3.  You *must* supply a different <old_file_log> for each service that
#        you define to use this plugin script - even if the different services
#        check the same <log_file> for pattern matches.  This is necessary
#        because of the way the script operates.
#
# Examples:
#
# Check for login failures in the syslog...
#
#   check_log /var/log/messages ./check_log.badlogins.old "LOGIN FAILURE"
#
# Check for port scan alerts generated by Psionic's PortSentry software...
#
#   check_log /var/log/message ./check_log.portscan.old "attackalert"
#

# Paths to commands used in this script.  These
# may have to be modified to match your system setup.

PATH="@TRUSTED_PATH@"
export PATH
PROGNAME=$(basename "$0")
PROGPATH=$(echo "$0" | sed -e 's,[\\/][^\\/][^\\/]*$,,')
REVISION="@NP_VERSION@"
PATH="@TRUSTED_PATH@"

export PATH

. "$PROGPATH"/utils.sh

print_usage() {
    echo "Usage: $PROGNAME -F logfile -O oldlog -q query"
    echo "Usage: $PROGNAME --help"
    echo "Usage: $PROGNAME --version"
    echo "     Aditional parameter:"
    echo "        -w (--max_warning) If used, determines the maximum matching value to return as warning, when finding more matching lines than this parameter will return as critical. If not used, will consider as default 0 (any matching will consider as critical)"
    echo "Usage: $PROGNAME -F logfile -O oldlog -q query -w <number>"
}

print_help() {
    print_revision "$PROGNAME" $REVISION
    echo ""
    print_usage
    echo ""
    echo "Log file pattern detector plugin for Nagios"
    echo ""
    support
}

# Make sure the correct number of command line
# arguments have been supplied

if [ $# -lt 1 ]; then
    print_usage
    exit "$STATE_UNKNOWN"
fi

# Grab the command line arguments

#logfile=$1
#oldlog=$2
#query=$3
exitstatus=$STATE_WARNING #default
while test -n "$1"; do
    case "$1" in
        --help)
            print_help
            exit "$STATE_OK"
            ;;
        -h)
            print_help
            exit "$STATE_OK"
            ;;
        --version)
            print_revision "$PROGNAME" $REVISION
            exit "$STATE_OK"
            ;;
        -V)
            print_revision "$PROGNAME" $REVISION
            exit "$STATE_OK"
            ;;
        --filename)
            logfile=$2
            shift
            ;;
        -F)
            logfile=$2
            shift
            ;;
        --oldlog)
            oldlog=$2
            shift
            ;;
        -O)
            oldlog=$2
            shift
            ;;
        --max_warning)
            MAX_WARNING=$2
            shift
            ;;
        -w)
            MAX_WARNING=$2
            shift
            ;;
        --query)
            query=$2
            shift
            ;;
        -q)
            query=$2
            shift
            ;;
        -x)
            exitstatus=$2
            shift
            ;;
        --exitstatus)
            exitstatus=$2
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            print_usage
            exit "$STATE_UNKNOWN"
            ;;
    esac
    shift
done

# If the source log file doesn't exist, exit

if [ ! -e "$logfile" ]; then
    echo "Log check error: Log file $logfile does not exist!"
    exit "$STATE_UNKNOWN"
elif [ ! -r "$logfile" ] ; then
    echo "Log check error: Log file $logfile is not readable!"
    exit "$STATE_UNKNOWN"
fi

# If the old log file doesn't exist, this must be the first time
# we're running this test, so copy the original log file over to
# the old diff file and exit

if [ ! -e "$oldlog" ]; then
    cat "$logfile" > "$oldlog"
    echo "Log check data initialized..."
    exit "$STATE_OK"
fi

# The old log file exists, so compare it to the original log now

# The temporary file that the script should use while
# processing the log file.
if [ -x /bin/mktemp ]; then
    tempdiff=$(/bin/mktemp /tmp/check_log.XXXXXXXXXX)
else
    tempdiff=$(/bin/date '+%H%M%S')
    tempdiff="/tmp/check_log.${tempdiff}"
    touch "$tempdiff"
    chmod 600 "$tempdiff"
fi

diff "$logfile" "$oldlog" | grep -v "^>" > "$tempdiff"

# Count the number of matching log entries we have and handle errors when grep fails
count=$(grep -c "$query" "$tempdiff" 2>&1)
if [[ $? -gt 1 ]];then
    echo "Log check error: $count"
    exit "$STATE_UNKNOWN"
fi

# Get the last matching entry in the diff file
lastentry=$(grep "$query" "$tempdiff" | tail -1)

rm -f "$tempdiff"
cat "$logfile" > "$oldlog"

if [ "$count" = "0" ]; then # no matches, exit with no error
    echo "Log check ok - 0 pattern matches found|match=$count;;;0"
    exitstatus=$STATE_OK
else # Print total matche count and the last entry we found
    echo "($count) $lastentry|match=$count;;;0"
    if [ "$MAX_WARNING" ] && [ "$count" -le "$MAX_WARNING" ] ; then
        exitstatus=$STATE_WARNING
    else
        exitstatus=$STATE_CRITICAL
    fi
fi

exit "$exitstatus"
