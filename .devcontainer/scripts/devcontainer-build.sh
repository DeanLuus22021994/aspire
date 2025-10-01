#!/bin/bash
# devcontainer-build.sh - Build and run devcontainer with logging

set -euo pipefail

LOG_DIR="/tmp/devcontainer-logs"
BUILD_LOG="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
UP_LOG="$LOG_DIR/up-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"

echo "=== Building DevContainer ==="
echo "Build log: $BUILD_LOG"
echo ""

if ! command -v devcontainer &> /dev/null; then
    echo "✗ devcontainer CLI not found"
    echo ""
    echo "Install with: npm install -g @devcontainers/cli"
    exit 1
fi

# Build the container
if devcontainer build --workspace-folder . --log-level trace 2>&1 | tee "$BUILD_LOG"; then
    echo ""
    echo "=== Build Complete ==="
else
    echo ""
    echo "=== Build Failed ==="
    echo "Check log: $BUILD_LOG"
    exit 1
fi

echo ""
echo "=== Starting DevContainer ==="
echo "Startup log: $UP_LOG"
echo ""

# Start the container
if devcontainer up --workspace-folder . --log-level trace 2>&1 | tee "$UP_LOG"; then
    echo ""
    echo "=== Container Started Successfully ==="
else
    echo ""
    echo "=== Startup Failed ==="
    echo "Check log: $UP_LOG"
    exit 1
fi

echo ""
echo "=== Log Summary ==="
echo "Build log: $BUILD_LOG"
echo "Startup log: $UP_LOG"
echo ""
echo "Last 30 lines of startup log:"
tail -n 30 "$UP_LOG"