#!/usr/bin/env bash

INTERVAL=5
LOG_FILE="monitor.log"

while true; do
    {
        printf -- '--- %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        free -h
        df -h
        uptime
        printf '\n'
    } >> "$LOG_FILE"
    sleep "$INTERVAL"
done
