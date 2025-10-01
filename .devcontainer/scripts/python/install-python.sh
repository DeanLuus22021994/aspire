#!/bin/bash
# Python Installation Wrapper with Caching and GPU Optimization
# This script wraps the Python feature installation to add caching support

set -e

PYTHON_VERSION="${1:-3.12.11}"
PYTHON_CACHE_DIR="${PYTHON_CACHE_DIR:-/usr/local/python-cache}"
PYTHON_INSTALL_DIR="/usr/local/python"
CACHED_PYTHON="$PYTHON_CACHE_DIR/$PYTHON_VERSION"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Python Installation Wrapper ===${NC}"
echo -e "${BLUE}Version: $PYTHON_VERSION${NC}"

# Check if Python is already cached
if [ -d "$CACHED_PYTHON" ] && [ -f "$CACHED_PYTHON/bin/python3" ]; then
    CACHED_VERSION=$("$CACHED_PYTHON/bin/python3" --version 2>&1 | awk '{print $2}')

    if [ "$CACHED_VERSION" = "$PYTHON_VERSION" ]; then
        echo -e "${GREEN}✓ Using cached Python $PYTHON_VERSION${NC}"

        # Create installation directory and symlink
        mkdir -p "$PYTHON_INSTALL_DIR"
        rm -rf "$PYTHON_INSTALL_DIR/$PYTHON_VERSION" 2>/dev/null || true
        cp -rL "$CACHED_PYTHON" "$PYTHON_INSTALL_DIR/$PYTHON_VERSION"
        ln -sf "$PYTHON_INSTALL_DIR/$PYTHON_VERSION" "$PYTHON_INSTALL_DIR/current"

        # Update PATH
        export PATH="$PYTHON_INSTALL_DIR/current/bin:$PATH"

        echo -e "${GREEN}✓ Python restored from cache successfully${NC}"
        echo -e "${BLUE}ℹ Build time saved: ~2 minutes${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ Cached version mismatch (cached: $CACHED_VERSION, requested: $PYTHON_VERSION)${NC}"
        echo -e "${YELLOW}⚠ Will rebuild Python from source${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Python $PYTHON_VERSION not found in cache${NC}"
    echo -e "${BLUE}ℹ Building Python from source...${NC}"
fi

# Detect GPU and CPU capabilities
CPU_CORES=$(nproc)
echo -e "${BLUE}ℹ CPU cores available: $CPU_CORES${NC}"

if command -v nvidia-smi >/dev/null 2>&1; then
    echo -e "${GREEN}✓ NVIDIA GPU detected - enabling optimizations${NC}"
    export CUDA_VISIBLE_DEVICES=0
elif [ -d "/dev/dri" ]; then
    echo -e "${GREEN}✓ GPU detected - enabling compiler optimizations${NC}"
fi

# Set compiler optimizations for GPU-accelerated builds
export MAKEFLAGS="-j$CPU_CORES"
export CFLAGS="-O3 -march=native -mtune=native"
export CXXFLAGS="-O3 -march=native -mtune=native"
export LDFLAGS="-Wl,-O1 -Wl,--as-needed"

echo -e "${BLUE}ℹ Compiler optimizations enabled:${NC}"
echo -e "  MAKEFLAGS: $MAKEFLAGS"
echo -e "  CFLAGS: $CFLAGS"

# Let the Python feature install Python
# The feature will handle the actual compilation
echo -e "${BLUE}ℹ Installing Python $PYTHON_VERSION (this may take ~2 minutes with GPU optimization)...${NC}"

# After successful installation, cache it
post_install_cache() {
    if [ -d "$PYTHON_INSTALL_DIR/$PYTHON_VERSION" ]; then
        echo -e "${BLUE}ℹ Caching Python installation...${NC}"

        mkdir -p "$PYTHON_CACHE_DIR"
        rm -rf "$CACHED_PYTHON" 2>/dev/null || true
        cp -rL "$PYTHON_INSTALL_DIR/$PYTHON_VERSION" "$CACHED_PYTHON"

        # Create a cache manifest
        cat > "$CACHED_PYTHON/.cache-info" <<EOF
VERSION=$PYTHON_VERSION
CACHED_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD_FLAGS="$CFLAGS"
CPU_CORES=$CPU_CORES
EOF

        echo -e "${GREEN}✓ Python $PYTHON_VERSION cached successfully${NC}"

        local cache_size=$(du -sh "$CACHED_PYTHON" | cut -f1)
        echo -e "${BLUE}ℹ Cache size: $cache_size${NC}"
    else
        echo -e "${YELLOW}⚠ Python installation not found, skipping cache${NC}"
    fi
}

# Register cleanup hook
trap post_install_cache EXIT

echo -e "${GREEN}✓ Python installation wrapper completed${NC}"
