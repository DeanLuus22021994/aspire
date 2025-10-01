#!/bin/bash
# Make all devcontainer scripts executable

chmod +x .devcontainer/scripts/devcontainer-*.sh
chmod +x .devcontainer/scripts/*.sh
chmod +x .devcontainer/scripts/lib/*.sh
chmod +x *.sh 2>/dev/null || true

echo "✓ All scripts are now executable"