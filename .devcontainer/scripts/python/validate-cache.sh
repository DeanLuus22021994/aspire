#!/bin/bash
#
# Python Cache Validation
# Validates Python cache integrity and provides cache management utilities
#

set -euo pipefail

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source libraries
source "${LIB_DIR}/colors.sh" 2>/dev/null || {
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
}

# Configuration
PYTHON_CACHE_DIR="${PYTHON_CACHE_DIR:-/usr/local/python-cache}"
PYTHON_TOOLS_CACHE_DIR="${PYTHON_TOOLS_CACHE_DIR:-/usr/local/py-utils-cache}"
PYTHON_VERSION="3.12.11"

#
# Validate Python binaries cache
#
validate_python_binaries() {
    local cached_python="${PYTHON_CACHE_DIR}/${PYTHON_VERSION}"

    if [ ! -d "$cached_python" ]; then
        echo -e "${YELLOW}⚠ Python ${PYTHON_VERSION} not in cache${NC}"
        return 1
    fi

    if [ ! -f "${cached_python}/bin/python3" ]; then
        echo -e "${RED}✗ Python binary not found in cache${NC}" >&2
        return 1
    fi

    # Validate version
    local cached_version
    cached_version=$("${cached_python}/bin/python3" --version 2>&1 | awk '{print $2}' || echo "unknown")

    if [ "$cached_version" != "$PYTHON_VERSION" ]; then
        echo -e "${YELLOW}⚠ Version mismatch: cached=${cached_version}, expected=${PYTHON_VERSION}${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ Python ${PYTHON_VERSION} cache valid${NC}"
    return 0
}

#
# Validate Python tools cache
#
validate_python_tools() {
    local tools=(
        "pipx" "flake8" "autopep8" "black" "yapf" "mypy" "pydocstyle"
        "pycodestyle" "bandit" "pipenv" "virtualenv" "pytest" "pylint"
    )

    local missing=0
    local found=0

    for tool in "${tools[@]}"; do
        if [ -d "${PYTHON_TOOLS_CACHE_DIR}/${tool}" ]; then
            ((found++))
        else
            ((missing++))
        fi
    done

    echo -e "${CYAN}→ Python tools cache status:${NC}"
    echo -e "  ${GREEN}✓${NC} Found: ${found}/${#tools[@]}"

    if [ $missing -gt 0 ]; then
        echo -e "  ${YELLOW}⚠${NC} Missing: ${missing}/${#tools[@]}"
        return 1
    fi

    echo -e "${GREEN}✓ All Python tools cached${NC}"
    return 0
}

#
# Get cache statistics
#
get_cache_stats() {
    echo -e "${CYAN}→ Cache Statistics:${NC}"

    if [ -d "$PYTHON_CACHE_DIR" ]; then
        local size
        size=$(du -sh "$PYTHON_CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        echo -e "  Python binaries: ${size}"
    else
        echo -e "  Python binaries: ${YELLOW}not initialized${NC}"
    fi

    if [ -d "$PYTHON_TOOLS_CACHE_DIR" ]; then
        local tools_size
        tools_size=$(du -sh "$PYTHON_TOOLS_CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        echo -e "  Python tools: ${tools_size}"
    else
        echo -e "  Python tools: ${YELLOW}not initialized${NC}"
    fi
}

# Main execution
main() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  Python Cache Validation"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local python_valid=0
    local tools_valid=0

    validate_python_binaries && python_valid=1
    validate_python_tools && tools_valid=1

    echo ""
    get_cache_stats
    echo ""

    if [ $python_valid -eq 1 ] && [ $tools_valid -eq 1 ]; then
        echo -e "${GREEN}✓ Python cache validation passed${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ Python cache incomplete or invalid${NC}"
        return 1
    fi
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
