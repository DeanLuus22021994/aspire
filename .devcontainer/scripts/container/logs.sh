#!/bin/bash
# devcontainer-logs.sh - Display devcontainer logs

set -euo pipefail

LOG_DIR="/tmp/devcontainer-logs"

echo "=== DevContainer Logs ==="
echo ""

if [ ! -d "$LOG_DIR" ] || [ -z "$(ls -A $LOG_DIR 2>/dev/null)" ]; then
    echo "No logs found in $LOG_DIR"
    echo "Run 'DevContainer: Build and Run with Logs' first"
    exit 0
fi

echo "Available logs in $LOG_DIR:"
ls -lh "$LOG_DIR"
echo ""

# Show most recent of each type
for log_type in build up rebuild; do
    latest_log=$(ls -t "$LOG_DIR/${log_type}-"*.log 2>/dev/null | head -n 1 || true)
    if [ -n "$latest_log" ]; then
        echo "--- Latest $log_type log (last 50 lines) ---"
        echo "File: $latest_log"
        echo ""
        tail -n 50 "$latest_log"
        echo ""
    fi
done

echo "=== To view full logs ==="
echo "cat $LOG_DIR/*.log"