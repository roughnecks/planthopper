#!/bin/bash

if [ ! -f "$1" ]; then
    echo "Usage: $0 configurationfile.conf"
fi

botdir=$(dirname $0)

if [ ! -d "$botdir/logs" ]; then
	mkdir -p "$botdir/logs"
fi

logfile=$botdir/logs/ph.log

cd $botdir || exit 2

# the bot never started, as there is no ph.pid, so append to logfile
if [ ! -f "$botdir/ph.pid" ]; then
    exec nohup perl planthopper.pl $1 >> "$logfile" 2>&1 &
    exit
fi

pid=$(cat $botdir/ph.pid)

if kill -0 $pid > /dev/null 2>&1 ; then
    exit
fi

# rotate the logs
if [ -f "$logfile" ]; then
    cat $logfile >> $logfile-`date +%F`;
    : > $logfile;
fi

echo -n $(date) >> "$logfile"
echo "Bot restarted by $0" >> "$logfile"
exec nohup perl planthopper.pl $1 >> "$logfile" 2>&1 &




