#!/bin/bash
# devcontainer-inspect.sh - Inspect running devcontainer

set -euo pipefail

echo "=== Current DevContainer Information ==="
echo ""

# Find running devcontainer
container_id=$(docker ps --filter "label=devcontainer.local_folder" --format '{{.ID}}' | head -n 1 || true)

if [ -z "$container_id" ]; then
    echo "No running devcontainer found"
    echo ""
    echo "Run 'DevContainer: Build and Run with Logs' first"
    echo ""
    echo "All containers:"
    docker ps -a
    exit 0
fi

echo "Container ID: $container_id"
echo ""

echo "--- Container Status ---"
docker ps --filter "id=$container_id" --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
echo ""

echo "--- Container Logs (last 50 lines) ---"
docker logs --tail 50 "$container_id"
echo ""

echo "--- Container Details ---"
if command -v jq &> /dev/null; then
    docker inspect "$container_id" | jq '.[0] | {
        Name: .Name,
        State: .State,
        Image: .Config.Image,
        Cmd: .Config.Cmd,
        Mounts: .Mounts | map({Source, Destination, Mode})
    }'
else
    docker inspect "$container_id"
fi

echo ""
echo "--- Quick Commands ---"
echo "Execute command: devcontainer exec --workspace-folder /projects/aspire <command>"
echo "Run user commands: devcontainer run-user-commands --workspace-folder /projects/aspire"
echo "View configuration: devcontainer read-configuration --workspace-folder /projects/aspire"
