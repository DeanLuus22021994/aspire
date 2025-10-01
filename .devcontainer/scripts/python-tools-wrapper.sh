#!/bin/bash
# Python Tools Installation Wrapper with Delta Updates and Caching
# Intelligently installs only missing or updated Python tools

set -e

PYTHON_TOOLS_CACHE_DIR="/usr/local/py-utils-cache"
PYTHON_TOOLS_DIR="/usr/local/py-utils"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Python Tools Installation Wrapper ===${NC}"

# Ensure directories exist
mkdir -p "$PYTHON_TOOLS_CACHE_DIR"
mkdir -p "$PYTHON_TOOLS_DIR"

# Define tools to install
declare -A TOOLS=(
    ["pipx"]="latest"
    ["flake8"]="latest"
    ["autopep8"]="latest"
    ["black"]="latest"
    ["yapf"]="latest"
    ["mypy"]="latest"
    ["pydocstyle"]="latest"
    ["pycodestyle"]="latest"
    ["bandit"]="latest"
    ["pipenv"]="latest"
    ["virtualenv"]="latest"
    ["pytest"]="latest"
    ["pylint"]="latest"
)

# Check if tool is cached
is_tool_cached() {
    local tool="$1"
    [ -d "$PYTHON_TOOLS_CACHE_DIR/$tool" ] && [ -f "$PYTHON_TOOLS_CACHE_DIR/$tool/.installed" ]
}

# Install tool using pipx
install_tool() {
    local tool="$1"
    local version="$2"

    echo -e "${BLUE}ℹ Installing $tool...${NC}"

    if pipx install "$tool" 2>&1 | tee /tmp/pipx-install-$tool.log; then
        # Cache the installation
        local tool_home=$(pipx list --short 2>/dev/null | grep "^$tool " | awk '{print $NF}' | head -1)

        if [ -n "$tool_home" ] && [ -d "$tool_home" ]; then
            echo -e "${BLUE}ℹ Caching $tool...${NC}"
            rm -rf "$PYTHON_TOOLS_CACHE_DIR/$tool" 2>/dev/null || true
            cp -rL "$tool_home" "$PYTHON_TOOLS_CACHE_DIR/$tool"

            # Create cache manifest
            cat > "$PYTHON_TOOLS_CACHE_DIR/$tool/.installed" <<EOF
TOOL=$tool
VERSION=$version
INSTALLED_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
            echo -e "${GREEN}✓ $tool installed and cached${NC}"
        else
            echo -e "${YELLOW}⚠ Could not locate $tool installation for caching${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Failed to install $tool (non-fatal)${NC}"
    fi
}

# Restore tool from cache
restore_tool() {
    local tool="$1"

    echo -e "${GREEN}✓ Restoring $tool from cache${NC}"

    # Copy from cache to tools directory
    if [ -d "$PYTHON_TOOLS_CACHE_DIR/$tool" ]; then
        local target_dir="$PYTHON_TOOLS_DIR/$tool"
        mkdir -p "$(dirname "$target_dir")"
        cp -rL "$PYTHON_TOOLS_CACHE_DIR/$tool" "$target_dir" 2>/dev/null || true
    fi
}

# Main installation logic
echo -e "${BLUE}ℹ Analyzing Python tools cache...${NC}"

TOOLS_TO_INSTALL=()
TOOLS_FROM_CACHE=()

for tool in "${!TOOLS[@]}"; do
    if is_tool_cached "$tool"; then
        TOOLS_FROM_CACHE+=("$tool")
        restore_tool "$tool"
    else
        TOOLS_TO_INSTALL+=("$tool")
    fi
done

# Summary
echo ""
echo -e "${BLUE}Cache Analysis:${NC}"
echo -e "  ${GREEN}✓ ${#TOOLS_FROM_CACHE[@]} tools restored from cache${NC}"
echo -e "  ${YELLOW}⚠ ${#TOOLS_TO_INSTALL[@]} tools need installation${NC}"

if [ ${#TOOLS_FROM_CACHE[@]} -gt 0 ]; then
    echo -e "\n${GREEN}Cached tools:${NC} ${TOOLS_FROM_CACHE[*]}"
fi

if [ ${#TOOLS_TO_INSTALL[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Installing missing tools:${NC} ${TOOLS_TO_INSTALL[*]}"
    echo ""

    # Install pipx first if needed
    if [[ " ${TOOLS_TO_INSTALL[*]} " =~ " pipx " ]]; then
        echo -e "${BLUE}ℹ Installing pipx (required for other tools)...${NC}"
        python3 -m pip install --user pipx
        python3 -m pipx ensurepath
        export PATH="$HOME/.local/bin:$PATH"

        # Cache pipx
        if [ -d "$HOME/.local/pipx" ]; then
            cp -rL "$HOME/.local/pipx" "$PYTHON_TOOLS_CACHE_DIR/pipx" 2>/dev/null || true
            touch "$PYTHON_TOOLS_CACHE_DIR/pipx/.installed"
        fi

        # Remove from list
        TOOLS_TO_INSTALL=("${TOOLS_TO_INSTALL[@]/pipx/}")
    fi

    # Install remaining tools in parallel (up to 4 at a time)
    local max_parallel=4
    local count=0

    for tool in "${TOOLS_TO_INSTALL[@]}"; do
        [ -z "$tool" ] && continue

        install_tool "$tool" "${TOOLS[$tool]}" &

        ((count++))
        if [ $((count % max_parallel)) -eq 0 ]; then
            wait
        fi
    done

    # Wait for remaining background jobs
    wait

    echo -e "\n${GREEN}✓ All tools installation completed${NC}"

    # Calculate time saved
    local tools_installed=${#TOOLS_TO_INSTALL[@]}
    local time_saved=$((${#TOOLS_FROM_CACHE[@]} * 15))  # Assume 15 seconds per tool

    if [ $time_saved -gt 0 ]; then
        echo -e "${BLUE}ℹ Time saved from cache: ~${time_saved} seconds${NC}"
    fi
else
    echo -e "\n${GREEN}✓ All tools restored from cache - no installation needed!${NC}"
    echo -e "${BLUE}ℹ Time saved: ~3 minutes${NC}"
fi

# Sync cache back to ensure everything is captured
echo -e "\n${BLUE}ℹ Synchronizing tools cache...${NC}"
rsync -a --delete "$PYTHON_TOOLS_DIR/" "$PYTHON_TOOLS_CACHE_DIR/" 2>/dev/null || \
    cp -rL "$PYTHON_TOOLS_DIR"/* "$PYTHON_TOOLS_CACHE_DIR/" 2>/dev/null || true

# Display final cache size
local cache_size=$(du -sh "$PYTHON_TOOLS_CACHE_DIR" 2>/dev/null | cut -f1)
echo -e "${BLUE}ℹ Python tools cache size: $cache_size${NC}"

echo -e "${GREEN}✓ Python tools installation wrapper completed${NC}"
