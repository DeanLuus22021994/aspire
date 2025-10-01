#!/bin/bash
#
# Pre-Rebuild Validation Script
# Validates all Python caching changes before attempting container rebuild
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  $1"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Track validation results
VALIDATION_PASSED=0
VALIDATION_WARNINGS=0
VALIDATION_ERRORS=0

print_header "DevContainer Rebuild Validation"

echo -e "${BLUE}Date:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BLUE}Host:${NC} $(hostname)"
echo -e "${BLUE}User:${NC} $(whoami)"
echo ""

#
# 1. Check devcontainer.json syntax
#
print_header "1. Validating devcontainer.json Syntax"

DEVCONTAINER_JSON="/projects/aspire/.devcontainer/devcontainer.json"

if [ ! -f "$DEVCONTAINER_JSON" ]; then
    print_error "devcontainer.json not found at $DEVCONTAINER_JSON"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
    # Check if jq is available
    if command -v jq &> /dev/null; then
        if jq empty "$DEVCONTAINER_JSON" 2>/dev/null; then
            print_success "devcontainer.json is valid JSON"
            VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
        else
            print_error "devcontainer.json has JSON syntax errors"
            jq empty "$DEVCONTAINER_JSON" 2>&1 | head -5
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        fi
    else
        print_warning "jq not installed, skipping JSON validation"
        VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
    fi
fi

#
# 2. Verify Python cache scripts exist and are executable
#
print_header "2. Validating Python Cache Scripts"

SCRIPTS=(
    "/projects/aspire/.devcontainer/scripts/lifecycle/init-python-cache.sh"
    "/projects/aspire/.devcontainer/scripts/python-install-wrapper.sh"
    "/projects/aspire/.devcontainer/scripts/python-tools-wrapper.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ ! -f "$script" ]; then
        print_error "Script not found: $script"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    elif [ ! -x "$script" ]; then
        print_error "Script not executable: $script"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    else
        print_success "Script OK: $(basename "$script")"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    fi
done

#
# 3. Check cleanup.sh modifications
#
print_header "3. Validating cleanup.sh Modifications"

CLEANUP_SCRIPT="/projects/aspire/.devcontainer/scripts/container/cleanup.sh"

if [ ! -f "$CLEANUP_SCRIPT" ]; then
    print_error "cleanup.sh not found"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
elif ! grep -q "Clean Python cache volumes" "$CLEANUP_SCRIPT"; then
    print_error "cleanup.sh missing Python cache management option"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
    print_success "cleanup.sh has Python cache management"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
fi

#
# 4. Verify devcontainer.json has required configurations
#
print_header "4. Validating devcontainer.json Configuration"

# Check for Python cache volumes
if grep -q "python-binaries-cache" "$DEVCONTAINER_JSON"; then
    print_success "python-binaries-cache volume configured"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
else
    print_error "python-binaries-cache volume not found in devcontainer.json"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if grep -q "python-tools-cache" "$DEVCONTAINER_JSON"; then
    print_success "python-tools-cache volume configured"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
else
    print_error "python-tools-cache volume not found in devcontainer.json"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Check for GPU configuration
if grep -q "MAKEFLAGS" "$DEVCONTAINER_JSON"; then
    print_success "MAKEFLAGS environment variable configured"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
else
    print_warning "MAKEFLAGS not found (parallel compilation may be slower)"
    VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
fi

# Check onCreateCommand order
if grep -q "chown.*sleep.*chmod.*init-python-cache" "$DEVCONTAINER_JSON"; then
    print_success "onCreateCommand has correct order (chown -> sleep -> init-python-cache)"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
else
    print_warning "onCreateCommand may not have optimal order"
    VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
fi

#
# 5. Check Docker daemon
#
print_header "5. Validating Docker Environment"

if ! command -v docker &> /dev/null; then
    print_error "Docker not found in PATH"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
elif ! docker info &> /dev/null; then
    print_error "Docker daemon not accessible (permission issue?)"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
    print_success "Docker daemon accessible"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))

    # Show Docker version
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
    print_info "Docker version: $DOCKER_VERSION"
fi

#
# 6. Check DevContainer CLI
#
print_header "6. Validating DevContainer CLI"

if ! command -v devcontainer &> /dev/null; then
    print_error "DevContainer CLI not found in PATH"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
    DEVCONTAINER_VERSION=$(devcontainer --version 2>/dev/null || echo "unknown")
    print_success "DevContainer CLI available: $DEVCONTAINER_VERSION"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
fi

#
# 7. Check existing cache volumes
#
print_header "7. Checking Existing Cache Volumes"

if docker volume ls --format '{{.Name}}' | grep -q "python-binaries-cache"; then
    CACHE_SIZE=$(docker run --rm -v python-binaries-cache:/cache alpine du -sh /cache 2>/dev/null | cut -f1 || echo "unknown")
    print_info "python-binaries-cache exists (size: $CACHE_SIZE)"
    print_warning "Cache exists - this will be a WARM rebuild (testing cache HIT)"
else
    print_info "python-binaries-cache does not exist - this will be a COLD rebuild (testing cache MISS)"
fi

if docker volume ls --format '{{.Name}}' | grep -q "python-tools-cache"; then
    TOOLS_CACHE_SIZE=$(docker run --rm -v python-tools-cache:/cache alpine du -sh /cache 2>/dev/null | cut -f1 || echo "unknown")
    print_info "python-tools-cache exists (size: $TOOLS_CACHE_SIZE)"
else
    print_info "python-tools-cache does not exist - tools will be installed fresh"
fi

#
# 8. GPU Detection
#
print_header "8. Detecting GPU Availability"

GPU_AVAILABLE="none"

# Check for NVIDIA GPU
if command -v nvidia-smi &> /dev/null; then
    if nvidia-smi &> /dev/null; then
        GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        print_success "NVIDIA GPU detected: $GPU_INFO"
        GPU_AVAILABLE="nvidia"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    fi
# Check for Intel/AMD GPU
elif [ -d "/dev/dri" ] && [ -n "$(ls -A /dev/dri 2>/dev/null)" ]; then
    print_info "Intel/AMD GPU detected at /dev/dri"
    GPU_AVAILABLE="intel-amd"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
else
    print_warning "No GPU detected - compilation will use CPU only"
    VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
fi

#
# 9. Check disk space
#
print_header "9. Checking Disk Space"

AVAILABLE_SPACE=$(df -h /var/lib/docker 2>/dev/null | awk 'NR==2 {print $4}' || echo "unknown")
print_info "Available disk space: $AVAILABLE_SPACE"

# Warn if less than 10GB available
AVAILABLE_GB=$(df -BG /var/lib/docker 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || echo "999")
if [ "$AVAILABLE_GB" -lt 10 ]; then
    print_warning "Low disk space (<10GB) - consider running cleanup.sh"
    VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
else
    print_success "Sufficient disk space available"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
fi

#
# 10. Script syntax validation
#
print_header "10. Validating Script Syntax"

for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        if bash -n "$script" 2>/dev/null; then
            print_success "$(basename "$script") syntax OK"
            VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
        else
            print_error "$(basename "$script") has syntax errors:"
            bash -n "$script" 2>&1 | head -5
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        fi
    fi
done

#
# Summary
#
print_header "Validation Summary"

echo -e "${GREEN}Passed:${NC}   $VALIDATION_PASSED"
echo -e "${YELLOW}Warnings:${NC} $VALIDATION_WARNINGS"
echo -e "${RED}Errors:${NC}   $VALIDATION_ERRORS"
echo ""

if [ $VALIDATION_ERRORS -eq 0 ]; then
    print_success "All critical validations passed!"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Ready to rebuild!${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}Rebuild command:${NC}"
    echo -e "  ${YELLOW}devcontainer up --workspace-folder /projects/aspire --remove-existing-container --log-level trace${NC}"
    echo ""
    echo -e "${BLUE}Expected behavior:${NC}"
    echo "  1. Permission fix: chown -> sleep 2 -> chmod (no permission errors)"
    echo "  2. init-python-cache.sh: Detects cache state and GPU"
    echo "  3. Python feature: Uses cache if available, or builds with GPU optimization"
    echo "  4. restore.sh: Executes successfully"
    echo ""
    echo -e "${BLUE}What to watch for:${NC}"
    echo "  • GPU detection: $GPU_AVAILABLE"
    echo "  • Python cache state: $([ -d "$(docker volume inspect python-binaries-cache --format '{{.Mountpoint}}' 2>/dev/null)" ] && echo "EXISTS (warm)" || echo "EMPTY (cold)")"
    echo "  • Expected build time: $([ -d "$(docker volume inspect python-binaries-cache --format '{{.Mountpoint}}' 2>/dev/null)" ] && echo "~4-5 min (cache hit)" || echo "~8-10 min (cache miss)")"
    echo ""
    exit 0
else
    print_error "Validation failed with $VALIDATION_ERRORS error(s)"
    echo ""
    echo -e "${RED}Please fix the errors above before rebuilding.${NC}"
    echo ""
    exit 1
fi
