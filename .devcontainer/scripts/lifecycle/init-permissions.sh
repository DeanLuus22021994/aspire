#!/bin/bash
#
# Initialize Workspace Permissions
# Ensures correct permissions before critical lifecycle operations
#

set -eo pipefail

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source libraries (colors first, then define fallbacks)
if ! source "${LIB_DIR}/colors.sh" 2>/dev/null; then
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi
source "${LIB_DIR}/permissions.sh"

# Configuration
WORKSPACE="${1:-/workspaces/aspire}"
MAX_WAIT="${2:-10}"

# Header
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  Initializing Workspace Permissions"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Ensure permissions
if ensure_permissions "$WORKSPACE" "$MAX_WAIT"; then
    echo -e "${GREEN}✓ Permission initialization complete${NC}"
    exit 0
else
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 1 ]; then
        echo -e "${YELLOW}⚠ Permission initialization timed out (non-fatal)${NC}"
        echo -e "${YELLOW}  Continuing with potentially incorrect permissions...${NC}"
        exit 0  # Non-fatal - let subsequent operations handle issues
    else
        echo -e "${RED}✗ Permission initialization failed${NC}" >&2
        exit 1
    fi
fi
