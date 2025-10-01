#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}ℹ Initializing Python cache system...${NC}"

# Cache directories
PYTHON_CACHE_DIR="${PYTHON_CACHE_DIR:-/usr/local/python-cache}"
PYTHON_TOOLS_CACHE_DIR="/usr/local/py-utils-cache"
PYTHON_INSTALL_DIR="/usr/local/python"
PYTHON_TOOLS_DIR="/usr/local/py-utils"

# Create cache directories if they don't exist
mkdir -p "$PYTHON_CACHE_DIR"
mkdir -p "$PYTHON_TOOLS_CACHE_DIR"

# Detect GPU availability
detect_gpu() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo -e "${GREEN}✓ NVIDIA GPU detected${NC}"
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || true
        export GPU_AVAILABLE="nvidia"
        return 0
    elif [ -d "/dev/dri" ]; then
        echo -e "${GREEN}✓ GPU device detected (Intel/AMD)${NC}"
        export GPU_AVAILABLE="other"
        return 0
    else
        echo -e "${YELLOW}⚠ No GPU detected - using CPU only${NC}"
        export GPU_AVAILABLE="none"
        return 1
    fi
}

# Check Python cache status
check_python_cache() {
    local python_version="3.12.11"
    local cached_python="$PYTHON_CACHE_DIR/$python_version"

    if [ -d "$cached_python" ] && [ -f "$cached_python/bin/python3" ]; then
        local version=$("$cached_python/bin/python3" --version 2>&1 | awk '{print $2}')
        if [ "$version" = "$python_version" ]; then
            echo -e "${GREEN}✓ Python $python_version found in cache${NC}"

            # Create symlink if it doesn't exist
            if [ ! -L "$PYTHON_INSTALL_DIR/current" ]; then
                mkdir -p "$PYTHON_INSTALL_DIR"
                ln -sf "$cached_python" "$PYTHON_INSTALL_DIR/current" 2>/dev/null || true
            fi

            return 0
        else
            echo -e "${YELLOW}⚠ Cached Python version mismatch (found: $version, expected: $python_version)${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠ Python $python_version not found in cache${NC}"
        return 1
    fi
}

# Check Python tools cache status
check_python_tools_cache() {
    local tools=(
        "pipx" "flake8" "autopep8" "black" "yapf" "mypy"
        "pydocstyle" "pycodestyle" "bandit" "pipenv" "virtualenv"
        "pytest" "pylint"
    )

    local cached_count=0
    local missing_tools=()

    for tool in "${tools[@]}"; do
        if [ -d "$PYTHON_TOOLS_CACHE_DIR/$tool" ]; then
            ((cached_count++))
        else
            missing_tools+=("$tool")
        fi
    done

    if [ $cached_count -eq ${#tools[@]} ]; then
        echo -e "${GREEN}✓ All ${#tools[@]} Python tools found in cache${NC}"

        # Restore symlinks if needed
        if [ ! -d "$PYTHON_TOOLS_DIR" ]; then
            mkdir -p "$PYTHON_TOOLS_DIR"
            cp -rL "$PYTHON_TOOLS_CACHE_DIR"/* "$PYTHON_TOOLS_DIR/" 2>/dev/null || true
        fi

        return 0
    elif [ $cached_count -gt 0 ]; then
        echo -e "${YELLOW}⚠ Found $cached_count/${#tools[@]} Python tools in cache${NC}"
        echo -e "${YELLOW}  Missing: ${missing_tools[*]}${NC}"
        return 1
    else
        echo -e "${YELLOW}⚠ No Python tools found in cache${NC}"
        return 1
    fi
}

# Calculate cache sizes
calculate_cache_sizes() {
    local python_cache_size=$(du -sh "$PYTHON_CACHE_DIR" 2>/dev/null | cut -f1)
    local tools_cache_size=$(du -sh "$PYTHON_TOOLS_CACHE_DIR" 2>/dev/null | cut -f1)

    echo -e "\n${BLUE}Cache Statistics:${NC}"
    echo -e "  Python binaries cache: ${python_cache_size}"
    echo -e "  Python tools cache:    ${tools_cache_size}"
}

# Main execution
echo ""
detect_gpu
echo ""

PYTHON_CACHED=false
TOOLS_CACHED=false

if check_python_cache; then
    PYTHON_CACHED=true
fi

echo ""

if check_python_tools_cache; then
    TOOLS_CACHED=true
fi

calculate_cache_sizes

# Export status for other scripts
export PYTHON_CACHED
export TOOLS_CACHED
export GPU_AVAILABLE

# Summary
echo ""
if [ "$PYTHON_CACHED" = true ] && [ "$TOOLS_CACHED" = true ]; then
    echo -e "${GREEN}✓ Python cache fully populated - build will be fast!${NC}"
    echo -e "${BLUE}ℹ Estimated build time savings: ~4 minutes${NC}"
elif [ "$PYTHON_CACHED" = true ] || [ "$TOOLS_CACHED" = true ]; then
    echo -e "${YELLOW}⚠ Python cache partially populated - first build will be slower${NC}"
    echo -e "${BLUE}ℹ Estimated build time: ~6-8 minutes${NC}"
else
    echo -e "${YELLOW}⚠ Python cache empty - first build will compile Python from source${NC}"
    echo -e "${BLUE}ℹ Estimated build time: ~8-10 minutes${NC}"
    if [ "$GPU_AVAILABLE" != "none" ]; then
        echo -e "${GREEN}ℹ GPU acceleration will be used for compilation${NC}"
    fi
fi

echo -e "${GREEN}✓ Python cache initialization complete${NC}"
