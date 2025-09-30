#!/bin/bash
# filepath: .devcontainer/init-env.sh

# This script is called by postCreateCommand to initialize the environment

set -euo pipefail

ENV_FILE=".devcontainer/.env"

# If .env file exists, source it for the current session
if [ -f "$ENV_FILE" ]; then
    echo "Loading environment from $ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
    echo "Environment variables loaded"
else
    echo "No .env file found at $ENV_FILE"
    echo "Run .devcontainer/setup-env.sh to create one"
fi

# Make scripts executable
chmod +x .devcontainer/*.sh 2>/dev/null || true

# Check if .env is in .gitignore
if [ -f .gitignore ] && [ -f "$ENV_FILE" ]; then
    if ! grep -q "\.devcontainer/\.env" .gitignore; then
        echo ""
        echo "WARNING: .devcontainer/.env is not in .gitignore!"
        echo "Add it to prevent committing secrets to version control"
    fi
fi