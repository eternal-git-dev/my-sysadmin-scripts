#!/usr/bin/env bash

set -u

/usr/local/bin/script.sh &
monitor_pid=$!
python3 -m http.server 8080 &
server_pid=$!

stop() {
    kill -TERM "$monitor_pid" "$server_pid" 2>/dev/null || true
    wait "$monitor_pid" "$server_pid" 2>/dev/null || true
    exit 0
}

trap stop INT TERM

wait -n "$monitor_pid" "$server_pid"
status=$?
kill -TERM "$monitor_pid" "$server_pid" 2>/dev/null || true
wait "$monitor_pid" "$server_pid" 2>/dev/null || true
exit "$status"
