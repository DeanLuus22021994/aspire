#!/bin/bash
# config.sh - Display parsed devcontainer configuration

set -euo pipefail

echo "=== DevContainer Configuration ==="
echo ""

if ! command -v devcontainer &> /dev/null; then
    echo "✗ devcontainer CLI not found"
    echo "Install with: npm install -g @devcontainers/cli"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Displaying raw configuration..."
    echo ""
    devcontainer read-configuration --workspace-folder /projects/aspire
    exit 0
fi

echo "Reading and formatting configuration..."
echo ""

config=$(devcontainer read-configuration --workspace-folder /projects/aspire)

# Display key configuration sections
echo "--- Container Name ---"
echo "$config" | jq -r '.configuration.name'
echo ""

echo "--- Features ---"
echo "$config" | jq -r '.configuration.features | keys[]'
echo ""

echo "--- Forwarded Ports ---"
echo "$config" | jq -r '.configuration.forwardPorts[]' 2>/dev/null || echo "None"
echo ""

echo "--- Resource Requirements ---"
echo "$config" | jq '.configuration.hostRequirements'
echo ""

echo "--- Lifecycle Commands ---"
echo "onCreate: $(echo "$config" | jq -r '.configuration.onCreateCommand // "none"' | head -c 80)..."
echo "postCreate: $(echo "$config" | jq -r '.configuration.postCreateCommand // "none"')"
echo "postStart: $(echo "$config" | jq -r '.configuration.postStartCommand // "none"' | head -c 80)..."
echo ""

echo "--- Mounts ---"
echo "$config" | jq -r '.configuration.mounts[]?' 2>/dev/null || echo "None (default bind mount only)"
echo ""

echo "--- Full JSON Configuration ---"
echo "To see full config: devcontainer read-configuration --workspace-folder /projects/aspire | jq ."
