#!/bin/bash

if [[ ! -f "$1" ]]; then
    printf '%s\n' "Usage: $0 configurationfile.conf"
fi

botdir="$(dirname $0)"

mkdir -p "$botdir/logs"

logfile="$botdir/logs/ph.log"

cd "$botdir" || exit 2

# the bot never started, as there is no ph.pid, so append to logfile
if [[ ! -f "$botdir/ph.pid" ]]; then
    exec nohup perl planthopper.pl "$1" >> "$logfile" 2>&1 &
    exit
fi

# check if the process exists
pid="$(< $botdir/ph.pid)"

if kill -0 "$pid" > /dev/null 2>&1; then
    exit
fi

# rotate the logs
if [[ -f "$logfile" ]]; then
    cat "$logfile" | gzip > "$logfile-$(date +%T_%F).gz" && > "$logfile"
fi

printf "$(date)\n" >> "$logfile"
printf '%s\n' "Bot restarted by $0" >> "$logfile"
exec nohup perl planthopper.pl "$1" >> "$logfile" 2>&1 &
