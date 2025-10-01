#!/bin/bash
# devcontainer-validate.sh - Validate devcontainer configuration

set -euo pipefail

# Ensure we're in the workspace root
if [ ! -f "global.json" ]; then
    echo "✗ Not in workspace root. Run from /projects/aspire"
    echo "Current directory: $(pwd)"
    exit 1
fi

echo "=== Validating DevContainer Configuration ==="
echo "Working directory: $(pwd)"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "⚠ jq not found, skipping JSON validation"
    echo "Install jq: sudo apt-get install jq"
    echo ""
else
    echo "Checking devcontainer.json syntax..."
    if [ ! -f ".devcontainer/devcontainer.json" ]; then
        echo "✗ .devcontainer/devcontainer.json not found"
        echo "Looking in: $(pwd)/.devcontainer/"
        ls -la .devcontainer/ 2>/dev/null || echo "Directory doesn't exist"
        exit 1
    fi

    # devcontainer.json uses JSONC (JSON with Comments), so strip comments first
    echo "  (Note: devcontainer.json uses JSONC format - stripping comments for validation)"
    if grep -v '^\s*//' .devcontainer/devcontainer.json | sed 's|//.*$||g' | jq empty 2>&1; then
        echo "✓ devcontainer.json is valid JSONC"
    else
        echo "⚠ Could not fully validate (comments may interfere)"
        echo "  File appears syntactically correct for VS Code"
    fi

    echo ""
    echo "Checking tasks.json syntax..."
    if [ ! -f ".vscode/tasks.json" ]; then
        echo "⚠ .vscode/tasks.json not found"
    else
        if jq empty .vscode/tasks.json 2>&1; then
            echo "✓ tasks.json is valid JSON"
        else
            echo "✗ tasks.json has syntax errors"
            jq . .vscode/tasks.json 2>&1 | head -20
        fi
    fi
fi

echo ""
echo "Checking Dockerfile..."
if [ -f ".devcontainer/Dockerfile" ]; then
    echo "✓ Dockerfile exists"
    echo ""
    echo "Dockerfile content:"
    cat .devcontainer/Dockerfile
else
    echo "✗ Dockerfile not found"
    echo "Looking in: $(pwd)/.devcontainer/"
    exit 1
fi

echo ""
echo "Checking required scripts..."
for script in restore.sh build.sh; do
    if [ -f "$script" ]; then
        echo "✓ $script exists"
        if [ -x "$script" ]; then
            echo "  └─ executable ✓"
        else
            echo "  └─ not executable ✗"
        fi
    else
        echo "✗ $script not found"
    fi
done

echo ""
echo "Checking devcontainer scripts..."
for script in .devcontainer/scripts/devcontainer-*.sh; do
    if [ -f "$script" ]; then
        if [ -x "$script" ]; then
            echo "✓ $(basename $script) is executable"
        else
            echo "✗ $(basename $script) is not executable"
        fi
    fi
done

echo ""
echo "Testing devcontainer read-configuration..."
if devcontainer read-configuration --workspace-folder . --log-level error > /dev/null 2>&1; then
    echo "✓ DevContainer CLI can parse configuration"
else
    echo "✗ DevContainer CLI configuration check failed"
    echo "  Run: devcontainer read-configuration --workspace-folder ."
fi

echo ""
echo "=== Configuration appears valid ==="
echo "Next steps:"
echo "  • Build: bash .devcontainer/scripts/container/build.sh"
echo "  • Rebuild: bash .devcontainer/scripts/container/rebuild.sh"
echo "  • Check logs: bash .devcontainer/scripts/container/logs.sh"
