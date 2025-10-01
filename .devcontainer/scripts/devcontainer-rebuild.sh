#!/bin/bash
# devcontainer-rebuild.sh - Rebuild devcontainer without cache

set -euo pipefail

LOG_DIR="/tmp/devcontainer-logs"
REBUILD_LOG="$LOG_DIR/rebuild-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"

echo "=== Rebuilding DevContainer (No Cache) ==="
echo "Log: $REBUILD_LOG"
echo ""

if ! command -v devcontainer &> /dev/null; then
    echo "✗ devcontainer CLI not found"
    echo "Install with: npm install -g @devcontainers/cli"
    exit 1
fi

if devcontainer build --workspace-folder . --no-cache --log-level trace 2>&1 | tee "$REBUILD_LOG"; then
    echo ""
    echo "=== Rebuild Complete ==="
    echo "Log: $REBUILD_LOG"
    echo ""
    echo "Last 50 lines:"
    tail -n 50 "$REBUILD_LOG"
else
    echo ""
    echo "=== Rebuild Failed ==="
    echo "Check log: $REBUILD_LOG"
    exit 1
fi