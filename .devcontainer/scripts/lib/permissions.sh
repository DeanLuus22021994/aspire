#!/bin/bash
#
# Permissions Management Library
# Provides robust permission handling with retry logic and validation
#

set -eo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! source "${SCRIPT_DIR}/colors.sh" 2>/dev/null; then
    # Fallback if colors.sh doesn't exist
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi

# Constants
readonly DEFAULT_MAX_WAIT=10
readonly DEFAULT_CHECK_INTERVAL=1
readonly DEFAULT_WORKSPACE="/workspaces/aspire"

#
# Ensure workspace permissions are correct
# Usage: ensure_permissions [workspace_path] [max_wait_seconds]
# Returns: 0 on success, 1 on timeout, 2 on error
#
ensure_permissions() {
    local workspace="${1:-$DEFAULT_WORKSPACE}"
    local max_wait="${2:-$DEFAULT_MAX_WAIT}"
    local wait_count=0

    echo -e "${CYAN}→ Ensuring permissions for: ${workspace}${NC}"

    # Check if workspace exists
    if [ ! -d "$workspace" ]; then
        echo -e "${RED}✗ Workspace not found: ${workspace}${NC}" >&2
        return 2
    fi

    # Attempt to fix permissions
    if ! _fix_permissions "$workspace"; then
        echo -e "${YELLOW}⚠ Could not run chown (may already have correct permissions)${NC}"
    fi

    # Wait for write access to critical directories
    local critical_dirs=(
        "${workspace}/artifacts"
        "${workspace}/.dotnet"
    )

    # Fix permissions on scripts that need to be executable
    local critical_scripts=(
        "${workspace}/eng/common/dotnet-install.sh"
        "${workspace}/eng/common/tools.sh"
    )

    for script in "${critical_scripts[@]}"; do
        if [ -f "$script" ]; then
            chmod +x "$script" 2>/dev/null || true
        fi
    done

    for dir in "${critical_dirs[@]}"; do
        if ! _wait_for_write_access "$dir" "$max_wait"; then
            echo -e "${RED}✗ Timeout waiting for write access: ${dir}${NC}" >&2
            return 1
        fi
    done

    echo -e "${GREEN}✓ Permissions verified${NC}"
    return 0
}

#
# Fix permissions for a path
# Usage: _fix_permissions <path>
# Returns: 0 on success, 1 on error (non-fatal)
#
_fix_permissions() {
    local path="$1"

    # Try to change ownership (works on native Linux, fails on WSL2 mounts)
    if chown -R vscode:vscode "$path" 2>/dev/null; then
        echo -e "${GREEN}✓ Changed ownership: ${path}${NC}"
        return 0
    fi

    # Fallback: make writable by all (works on WSL2 mounts)
    if chmod -R a+w "$path" 2>/dev/null; then
        echo -e "${GREEN}✓ Made writable: ${path}${NC}"
        return 0
    fi

    return 1
}

#
# Wait for write access to a directory
# Usage: _wait_for_write_access <dir_path> [max_wait_seconds]
# Returns: 0 if writable, 1 on timeout
#
_wait_for_write_access() {
    local dir="$1"
    local max_wait="${2:-$DEFAULT_MAX_WAIT}"
    local wait_count=0

    # Create directory if it doesn't exist
    mkdir -p "$dir" 2>/dev/null || true

    # Try to fix permissions immediately
    if _fix_permissions "$dir" 2>/dev/null; then
        # Check if vscode user exists (container) or just check world-writable (host)
        if id vscode &>/dev/null; then
            # In container: check vscode user can write
            if sudo -u vscode test -w "$dir" 2>/dev/null; then
                echo -e "${GREEN}✓ Write access verified (vscode user): ${dir}${NC}"
                return 0
            fi
        else
            # On host or vscode doesn't exist: check if world-writable
            if [ -w "$dir" ]; then
                echo -e "${GREEN}✓ Write access verified: ${dir}${NC}"
                return 0
            fi
        fi
    fi

    # Retry loop if initial attempt failed
    while true; do
        if [ $wait_count -ge "$max_wait" ]; then
            echo -e "${YELLOW}⚠ Timeout after ${max_wait}s waiting for: ${dir}${NC}" >&2
            return 1
        fi

        sleep "$DEFAULT_CHECK_INTERVAL"
        wait_count=$((wait_count + DEFAULT_CHECK_INTERVAL))

        # Try to fix permissions again
        if ! _fix_permissions "$dir" 2>/dev/null; then
            continue
        fi

        # Check again
        if id vscode &>/dev/null; then
            if sudo -u vscode test -w "$dir" 2>/dev/null; then
                echo -e "${GREEN}✓ Write access verified (vscode user): ${dir}${NC}"
                return 0
            fi
        else
            if [ -w "$dir" ]; then
                echo -e "${GREEN}✓ Write access verified: ${dir}${NC}"
                return 0
            fi
        fi
    done
}

#
# Validate permissions for critical paths
# Usage: validate_permissions [workspace_path]
# Returns: 0 if all checks pass, 1 otherwise
#
validate_permissions() {
    local workspace="${1:-$DEFAULT_WORKSPACE}"
    local failed=0

    echo -e "${CYAN}→ Validating permissions...${NC}"

    local critical_paths=(
        "${workspace}/artifacts"
        "${workspace}/.dotnet"
        "${workspace}/eng"
    )

    for path in "${critical_paths[@]}"; do
        if [ ! -e "$path" ]; then
            echo -e "${YELLOW}⚠ Path does not exist: ${path}${NC}"
            continue
        fi

        if [ ! -w "$path" ]; then
            echo -e "${RED}✗ No write access: ${path}${NC}" >&2
            failed=1
        else
            echo -e "${GREEN}✓ Write access OK: ${path}${NC}"
        fi
    done

    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}✓ All permission checks passed${NC}"
    fi

    return $failed
}

# Export functions if script is sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f ensure_permissions
    export -f validate_permissions
fi
