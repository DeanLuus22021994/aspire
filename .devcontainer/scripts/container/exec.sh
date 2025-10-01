#!/bin/bash
# exec.sh - Execute commands in the running devcontainer

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: bash .devcontainer/scripts/container/exec.sh <command> [args...]"
    echo ""
    echo "Examples:"
    echo "  bash .devcontainer/scripts/container/exec.sh bash"
    echo "  bash .devcontainer/scripts/container/exec.sh dotnet --version"
    echo "  bash .devcontainer/scripts/container/exec.sh 'echo \$PATH'"
    echo ""
    echo "This uses 'devcontainer exec' to run commands in the container with proper environment."
    exit 1
fi

# Check if container is running
container_id=$(docker ps --filter "label=devcontainer.local_folder=/projects/aspire" --format '{{.ID}}' | head -n 1 || true)

if [ -z "$container_id" ]; then
    echo "✗ No running devcontainer found"
    echo ""
    echo "Start container first:"
    echo "  bash .devcontainer/scripts/container/build.sh"
    exit 1
fi

echo "Executing in container: $*"
echo ""

devcontainer exec --workspace-folder /projects/aspire "$@"
