#!/bin/bash
# init-cache.sh - Initialize cache directories and symlinks
# Single Responsibility: Set up workspace caching for optimal performance

set -euo pipefail

# Source utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$SCRIPT_DIR/../lib"
source "$LIB_DIR/colors.sh" 2>/dev/null || true

print_info "Initializing workspace cache..."

# Create cache directory structure if it doesn't exist
mkdir -p /workspace-cache/nuget
mkdir -p /workspace-cache/artifacts
mkdir -p /workspace-cache/.dotnet
mkdir -p /workspaces/aspire/.dotnet

# Set proper ownership for vscode user
chown -R vscode:vscode /workspace-cache 2>/dev/null || true
chown -R vscode:vscode /workspaces/aspire/.dotnet 2>/dev/null || true

# Create symlinks if workspace .dotnet doesn't have content
if [ ! -d "/workspaces/aspire/.dotnet/sdk" ] && [ -d "/workspace-cache/.dotnet/sdk" ]; then
    print_info "Linking cached .dotnet SDK to workspace..."
    rm -rf /workspaces/aspire/.dotnet 2>/dev/null || true
    ln -sf /workspace-cache/.dotnet /workspaces/aspire/.dotnet 2>/dev/null || print_warning "Could not link .dotnet (permissions)"
    [ -L "/workspaces/aspire/.dotnet" ] && print_success ".dotnet SDK linked from cache"
fi

# Create symlink for artifacts if cache exists (non-fatal)
if [ -d "/workspace-cache/artifacts" ] && [ ! -L "/workspaces/aspire/artifacts-cache" ]; then
    if ln -sf /workspace-cache/artifacts /workspaces/aspire/artifacts-cache 2>/dev/null; then
        print_info "Linked artifacts cache"
    else
        print_warning "Could not link artifacts cache (non-critical, workspace may be read-only)"
    fi
fi

# Verify cache setup
if [ -d "/workspace-cache/nuget" ]; then
    nuget_count=$(find /workspace-cache/nuget -type f 2>/dev/null | wc -l)
    print_info "NuGet cache contains $nuget_count packages"
fi

# Display cache statistics
echo ""
print_subheader "Cache Statistics"
du -sh /workspace-cache/* 2>/dev/null || echo "Cache directories created (empty)"

print_success "Cache initialization complete"
exit 0
