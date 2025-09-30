# DevContainer Development Debt - Sprint 2: CI/CD & Architecture Requirements
# Version: 3.0.0
# Last Updated: 2024-10-31
# Status: Implementation Ready with Full Traceability

## Document Purpose & Traceability

This document provides detailed implementation specifications for Sprint 2 requirements focusing on CI/CD automation, architecture improvements, and testing infrastructure. Each requirement is tagged for complete traceability with automated search and AI assistance capabilities.

**Tag Format:** `[TAG-{Category}-{ID}]` where:
- Category: ARCH (Architecture), CICD (CI/CD), TEST (Testing), etc.
- ID: Three-digit requirement identifier

## 🚀 Sprint 2 Overview: CI/CD & Automation

### Sprint Goals
- Automated prebuild pipeline with 95% cache hit rate
- Multi-architecture support (AMD64 + ARM64)
- Registry-based caching for team collaboration
- Comprehensive testing infrastructure
- Performance optimization through precompilation

---

## Architecture Requirement Specifications

### [TAG-PERF-006] REQ-PERF-006: Registry Caching
**Reference:** TECHNICAL_DEBT_REPORT.md#req-perf-006
**Priority:** P1 | **Sprint:** 2 | **Effort:** 2 days | **Owner:** DevOps
**Technical Debt ID:** TD-006

#### Problem Statement
No shared cache between team members causing:
- Every developer rebuilds from scratch
- No cache reuse across CI/CD runs
- 7+ minute builds for each team member
- Wasted compute resources

#### Complete Registry Cache Implementation

##### GitHub Container Registry Configuration
````yaml
# filepath: .github/workflows/devcontainer-registry-cache.yml
# [TAG-PERF-006-WORKFLOW]

name: DevContainer Registry Cache Builder

on:
  push:
    branches: [main, release/*, feature/*]
    paths:
      - '.devcontainer/**'
      - 'global.json'
      - 'Directory.*.props'
      - 'eng/Versions.props'
      - 'NuGet.config'
  pull_request:
    paths:
      - '.devcontainer/**'
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC for cache warming
  workflow_dispatch:
    inputs:
      platforms:
        description: 'Platforms to build (comma-separated)'
        required: false
        default: 'linux/amd64,linux/arm64'
      cache_mode:
        description: 'Cache mode (min, max, inline)'
        required: false
        default: 'max'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}-devcontainer
  DOCKER_BUILDKIT: 1
  COMPOSE_DOCKER_CLI_BUILD: 1
  BUILDKIT_PROGRESS: plain

jobs:
  # [TAG-PERF-006-SETUP] Setup job for matrix generation
  setup:
    runs-on: ubuntu-latest
    outputs:
      platforms: ${{ steps.platforms.outputs.list }}
      cache_key: ${{ steps.cache.outputs.key }}
    steps:
      - name: Determine platforms
        id: platforms
        run: |
          if [ -n "${{ inputs.platforms }}" ]; then
            PLATFORMS="${{ inputs.platforms }}"
          else
            PLATFORMS="linux/amd64,linux/arm64"
          fi
          # Convert to JSON array for matrix
          echo "list=$(echo $PLATFORMS | jq -R 'split(",")' -c)" >> $GITHUB_OUTPUT
      
      - name: Generate cache key
        id: cache
        run: |
          echo "key=devcontainer-${{ hashFiles('.devcontainer/**') }}-$(date +%Y%m%d)" >> $GITHUB_OUTPUT

  # [TAG-PERF-006-BUILD] Parallel build job for each platform
  build-and-cache:
    needs: setup
    runs-on: ubuntu-latest
    timeout-minutes: 45
    permissions:
      contents: read
      packages: write
      id-token: write
    
    strategy:
      fail-fast: false
      matrix:
        platform: ${{ fromJson(needs.setup.outputs.platforms) }}
        include:
          - platform: linux/amd64
            arch: amd64
            runner: ubuntu-latest
          - platform: linux/arm64
            arch: arm64
            runner: ubuntu-latest
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          submodules: recursive
      
      # [TAG-PERF-006-QEMU] Setup QEMU for multi-arch
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3
        with:
          platforms: all
      
      # [TAG-PERF-006-BUILDX] Setup BuildX with optimized config
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
        with:
          version: latest
          driver-opts: |
            image=moby/buildkit:v0.12.0
            network=host
          buildkitd-flags: |
            --debug
            --config=/tmp/buildkitd.toml
          config-inline: |
            [worker.oci]
              max-parallelism = 4
            [gc]
              enabled = true
              keepBytes = 10737418240
              keepDuration = 604800
            [registry."ghcr.io"]
              mirrors = ["mirror.gcr.io"]
      
      # [TAG-PERF-006-LOGIN] Registry authentication
      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      # [TAG-PERF-006-META] Generate metadata and tags
      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch,suffix=-${{ matrix.arch }}
            type=ref,event=pr,suffix=-${{ matrix.arch }}
            type=semver,pattern={{version}},suffix=-${{ matrix.arch }}
            type=semver,pattern={{major}}.{{minor}},suffix=-${{ matrix.arch }}
            type=sha,prefix={{branch}}-,suffix=-${{ matrix.arch }}
            type=raw,value=latest-${{ matrix.arch }},enable={{is_default_branch}}
            type=raw,value=cache-${{ matrix.arch }}
            type=raw,value=cache-${{ matrix.arch }}-{{date 'YYYYMMDD'}}
      
      # [TAG-PERF-006-CACHE-RESTORE] Restore BuildKit cache
      - name: Restore BuildKit cache
        uses: actions/cache/restore@v3
        with:
          path: /tmp/.buildx-cache
          key: buildx-${{ matrix.arch }}-${{ needs.setup.outputs.cache_key }}
          restore-keys: |
            buildx-${{ matrix.arch }}-
            buildx-
      
      # [TAG-PERF-006-BUILD-PUSH] Build and push with maximum caching
      - name: Build and push Docker image
        id: build
        uses: docker/build-push-action@v5
        with:
          context: .
          file: .devcontainer/Dockerfile.optimized
          platforms: ${{ matrix.platform }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: |
            type=gha,scope=${{ matrix.arch }}
            type=registry,ref=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:cache-${{ matrix.arch }}
            type=registry,ref=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest-${{ matrix.arch }}
            type=local,src=/tmp/.buildx-cache
          cache-to: |
            type=gha,scope=${{ matrix.arch }},mode=${{ inputs.cache_mode || 'max' }}
            type=registry,ref=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:cache-${{ matrix.arch }},mode=${{ inputs.cache_mode || 'max' }}
            type=local,dest=/tmp/.buildx-cache-new,mode=${{ inputs.cache_mode || 'max' }}
          build-args: |
            BUILDKIT_INLINE_CACHE=1
            BUILD_DATE=${{ github.event.repository.updated_at }}
            VCS_REF=${{ github.sha }}
            VERSION=${{ github.ref_name }}
            TARGETPLATFORM=${{ matrix.platform }}
          secrets: |
            "github_token=${{ secrets.GITHUB_TOKEN }}"
          outputs: |
            type=image,name=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }},push-by-digest=true,name-canonical=true,push=true
      
      # [TAG-PERF-006-CACHE-SAVE] Save BuildKit cache for next run
      - name: Save BuildKit cache
        uses: actions/cache/save@v3
        if: always()
        with:
          path: /tmp/.buildx-cache-new
          key: buildx-${{ matrix.arch }}-${{ needs.setup.outputs.cache_key }}
      
      # [TAG-PERF-006-METRICS] Report build metrics
      - name: Report build metrics
        if: always()
        run: |
          echo "📊 Build Metrics for ${{ matrix.platform }}"
          echo "Build time: ${{ steps.build.outputs.build-time || 'N/A' }}"
          echo "Image digest: ${{ steps.build.outputs.digest }}"
          echo "Cache mode: ${{ inputs.cache_mode || 'max' }}"
          
          # Calculate cache effectiveness
          docker buildx du --verbose || true
````

##### Local Developer Cache Usage
````bash
#!/bin/bash
# filepath: .devcontainer/scripts/use-registry-cache.sh
# [TAG-PERF-006-LOCAL-SCRIPT]

set -euo pipefail

# Configuration
REGISTRY="ghcr.io"
IMAGE_NAME="microsoft/aspire-devcontainer"
CACHE_TAG="cache"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 Configuring registry cache for local development${NC}"

# [TAG-PERF-006-LOCAL-AUTH] Authenticate to registry
authenticate_registry() {
    echo -e "${YELLOW}Authenticating to GitHub Container Registry...${NC}"
    
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        echo "$GITHUB_TOKEN" | docker login $REGISTRY -u "$GITHUB_USER" --password-stdin
    elif [ -n "${CR_PAT:-}" ]; then
        echo "$CR_PAT" | docker login $REGISTRY -u USERNAME --password-stdin
    else
        echo "⚠️ No authentication token found. Using anonymous access (limited rate)."
    fi
}

# [TAG-PERF-006-LOCAL-PULL] Pull cache images
pull_cache_images() {
    local PLATFORM="${1:-linux/amd64}"
    local ARCH=$(echo $PLATFORM | cut -d'/' -f2)
    
    echo -e "${YELLOW}Pulling cache images for $PLATFORM...${NC}"
    
    # Pull cache layers
    docker pull --platform=$PLATFORM $REGISTRY/$IMAGE_NAME:$CACHE_TAG-$ARCH || true
    docker pull --platform=$PLATFORM $REGISTRY/$IMAGE_NAME:latest-$ARCH || true
}

# [TAG-PERF-006-LOCAL-BUILD] Build with registry cache
build_with_cache() {
    local PLATFORM="${1:-linux/amd64}"
    local ARCH=$(echo $PLATFORM | cut -d'/' -f2)
    
    echo -e "${YELLOW}Building with registry cache...${NC}"
    
    docker buildx build \
        --platform=$PLATFORM \
        --cache-from=type=registry,ref=$REGISTRY/$IMAGE_NAME:$CACHE_TAG-$ARCH \
        --cache-from=type=registry,ref=$REGISTRY/$IMAGE_NAME:latest-$ARCH \
        --cache-to=type=inline \
        --tag aspire-devcontainer:local \
        --file .devcontainer/Dockerfile.optimized \
        --load \
        .
}

# [TAG-PERF-006-LOCAL-COMPOSE] Docker Compose with registry cache
create_compose_override() {
    cat > .devcontainer/docker-compose.cache-override.yml <<EOF
# Generated by use-registry-cache.sh
# [TAG-PERF-006-LOCAL-COMPOSE-OVERRIDE]
services:
  dev:
    build:
      cache_from:
        - type=registry,ref=$REGISTRY/$IMAGE_NAME:cache-amd64
        - type=registry,ref=$REGISTRY/$IMAGE_NAME:cache-arm64
        - type=registry,ref=$REGISTRY/$IMAGE_NAME:latest
      cache_to:
        - type=inline
EOF
    
    echo "✅ Created docker-compose.cache-override.yml"
}

# Main execution
main() {
    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) PLATFORM="linux/amd64" ;;
        aarch64|arm64) PLATFORM="linux/arm64" ;;
        *) PLATFORM="linux/amd64" ;;
    esac
    
    echo "🔍 Detected platform: $PLATFORM"
    
    # Execute steps
    authenticate_registry
    pull_cache_images "$PLATFORM"
    create_compose_override
    build_with_cache "$PLATFORM"
    
    echo -e "${GREEN}✨ Registry cache configured successfully!${NC}"
    echo "To use: docker-compose -f docker-compose.yml -f docker-compose.cache-override.yml up"
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
````

#### Verification Tests
````bash
#!/bin/bash
# filepath: .devcontainer/tests/verify-registry-cache.sh
# [TAG-PERF-006-TEST]

set -euo pipefail

echo "🧪 Testing registry cache effectiveness..."

# Test 1: Registry accessibility
echo -n "TEST-PERF-006-A: Registry accessible... "
if curl -s https://ghcr.io/v2/ | grep -q "401"; then
    echo "✅ PASS"
else
    echo "❌ FAIL: Cannot reach registry"
    exit 1
fi

# Test 2: Cache image exists
echo -n "TEST-PERF-006-B: Cache images available... "
MANIFEST=$(docker manifest inspect ghcr.io/microsoft/aspire-devcontainer:cache-amd64 2>/dev/null || echo "failed")
if [ "$MANIFEST" != "failed" ]; then
    echo "✅ PASS"
else
    echo "⚠️ WARNING: Cache images not found (may be first run)"
fi

# Test 3: Build with cache
echo -n "TEST-PERF-006-C: Building with registry cache... "
BUILD_START=$(date +%s)
docker buildx build \
    --cache-from=type=registry,ref=ghcr.io/microsoft/aspire-devcontainer:cache-amd64 \
    --tag test:registry-cache \
    -f .devcontainer/Dockerfile.optimized \
    . >/tmp/registry-build.log 2>&1

BUILD_END=$(date +%s)
BUILD_TIME=$((BUILD_END - BUILD_START))

if [ $BUILD_TIME -lt 180 ]; then
    echo "✅ PASS (${BUILD_TIME}s)"
else
    echo "⚠️ SLOW (${BUILD_TIME}s - cache may not be effective)"
fi

# Test 4: Cache hit rate
echo -n "TEST-PERF-006-D: Cache hit rate... "
CACHE_HITS=$(grep -c "CACHED" /tmp/registry-build.log || echo 0)
TOTAL_STEPS=$(grep -c "RUN\|COPY\|FROM" /tmp/registry-build.log || echo 1)
HIT_RATE=$((CACHE_HITS * 100 / TOTAL_STEPS))

if [ $HIT_RATE -gt 70 ]; then
    echo "✅ PASS (${HIT_RATE}%)"
else
    echo "⚠️ LOW (${HIT_RATE}% - expected >70%)"
fi

echo ""
echo "📊 Registry Cache Summary:"
echo "  Build time: ${BUILD_TIME}s"
echo "  Cache hit rate: ${HIT_RATE}%"
````

---

### [TAG-PERF-007] REQ-PERF-007: Volume Persistence
**Reference:** TECHNICAL_DEBT_REPORT.md#req-perf-007
**Priority:** P1 | **Sprint:** 1 | **Effort:** 1 day | **Owner:** DevOps
**Technical Debt ID:** TD-007

#### Problem Statement
No persistent volumes causing:
- NuGet packages lost on container rebuild (1.5GB)
- npm packages lost on container rebuild (500MB)
- Build artifacts lost on container rebuild (2GB)
- VS Code extensions reinstalled every time (200MB)

#### Complete Volume Persistence Implementation

````yaml
# filepath: .devcontainer/docker-compose.volumes.yml
# [TAG-PERF-007-COMPOSE]

version: '3.8'

services:
  dev:
    volumes:
      # [TAG-PERF-007-SOURCE] Source code mount with performance optimization
      - type: bind
        source: ..
        target: /workspaces/aspire
        consistency: delegated  # macOS performance optimization
      
      # [TAG-PERF-007-NUGET] NuGet package caches
      - type: volume
        source: nuget-packages
        target: /home/vscode/.nuget/packages
        volume:
          nocopy: false  # Copy existing content on first mount
      
      - type: volume
        source: nuget-http-cache
        target: /home/vscode/.local/share/NuGet/http-cache
      
      - type: volume
        source: nuget-plugins-cache
        target: /home/vscode/.local/share/NuGet/plugins-cache
      
      # [TAG-PERF-007-DOTNET] .NET tool cache
      - type: volume
        source: dotnet-tools
        target: /home/vscode/.dotnet/tools
      
      # [TAG-PERF-007-BUILD] Build output caches
      - type: volume
        source: obj-cache
        target: /workspaces/aspire/obj
      
      - type: volume
        source: bin-cache
        target: /workspaces/aspire/bin
      
      - type: volume
        source: artifacts-cache
        target: /workspaces/aspire/artifacts
      
      # [TAG-PERF-007-VSCODE] VS Code server and extensions
      - type: volume
        source: vscode-server
        target: /home/vscode/.vscode-server
      
      - type: volume
        source: vscode-server-insiders
        target: /home/vscode/.vscode-server-insiders
      
      # [TAG-PERF-007-NODEJS] Node.js caches
      - type: volume
        source: npm-cache
        target: /home/vscode/.npm
      
      - type: volume
        source: node-modules
        target: /workspaces/aspire/playground/TestShop/node_modules
      
      # [TAG-PERF-007-PYTHON] Python cache
      - type: volume
        source: pip-cache
        target: /home/vscode/.cache/pip
      
      # [TAG-PERF-007-HISTORY] Command history persistence
      - type: volume
        source: bash-history
        target: /commandhistory
      
      # [TAG-PERF-007-SSH] SSH keys (read-only for security)
      - type: bind
        source: ${HOME}/.ssh
        target: /home/vscode/.ssh
        read_only: true
        consistency: cached
      
      # [TAG-PERF-007-GIT] Git configuration
      - type: bind
        source: ${HOME}/.gitconfig
        target: /home/vscode/.gitconfig.host
        read_only: true
        consistency: cached

# [TAG-PERF-007-VOLUME-DEFINITIONS] Volume definitions with optimized drivers
volumes:
  # NuGet volumes - persisted on host
  nuget-packages:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${HOME}/.aspire-devcontainer/nuget-packages
  
  nuget-http-cache:
    driver: local
    driver_opts:
      type: tmpfs
      o: size=2g,uid=1000,gid=1000,mode=0755
  
  nuget-plugins-cache:
    driver: local
    driver_opts:
      type: tmpfs
      o: size=100m,uid=1000,gid=1000,mode=0755
  
  # .NET tools
  dotnet-tools:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${HOME}/.aspire-devcontainer/dotnet-tools
  
  # Build outputs - tmpfs for performance
  obj-cache:
    driver: local
    driver_opts:
      type: tmpfs
      o: size=8g,uid=1000,gid=1000,mode=0755
  
  bin-cache:
    driver: local
    driver_opts:
      type: tmpfs
      o: size=4g,uid=1000,gid=1000,mode=0755
  
  artifacts-cache:
    driver: local
    driver_opts:
      type: tmpfs
      o: size=4g,uid=1000,gid=1000,mode=0755
  
  # VS Code
  vscode-server:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${HOME}/.aspire-devcontainer/vscode-server
  
  vscode-server-insiders:
    driver: local
  
  # Node.js
  npm-cache:
    driver: local
    driver_opts:
      type: tmpfs
      o: size=1g,uid=1000,gid=1000,mode=0755
  
  node-modules:
    driver: local
  
  # Python
  pip-cache:
    driver: local
    driver_opts:
      type: tmpfs
      o: size=500m,uid=1000,gid=1000,mode=0755
  
  # History
  bash-history:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${HOME}/.aspire-devcontainer/bash-history
````

##### Volume Management Script
````bash
#!/bin/bash
# filepath: .devcontainer/scripts/manage-volumes.sh
# [TAG-PERF-007-SCRIPT]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
VOLUME_BASE_DIR="${HOME}/.aspire-devcontainer"
PROJECT_NAME="aspire"

# [TAG-PERF-007-INIT] Initialize persistent volume directories
init_volumes() {
    echo -e "${BLUE}🔧 Initializing persistent volume directories...${NC}"
    
    local dirs=(
        "$VOLUME_BASE_DIR/nuget-packages"
        "$VOLUME_BASE_DIR/dotnet-tools"
        "$VOLUME_BASE_DIR/vscode-server"
        "$VOLUME_BASE_DIR/bash-history"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            echo "  ✅ Created: $dir"
        else
            echo "  ℹ️ Exists: $dir"
        fi
    done
    
    # Set permissions
    chmod -R 755 "$VOLUME_BASE_DIR"
    
    # Initialize bash history file
    touch "$VOLUME_BASE_DIR/bash-history/.bash_history"
}

# [TAG-PERF-007-STATUS] Check volume status
check_volume_status() {
    echo -e "${BLUE}📊 Volume Status Report${NC}"
    
    # Docker volumes
    echo -e "\n${YELLOW}Docker Volumes:${NC}"
    docker volume ls --filter "name=${PROJECT_NAME}" --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}"
    
    # Host directories
    echo -e "\n${YELLOW}Host Directories:${NC}"
    if [ -d "$VOLUME_BASE_DIR" ]; then
        du -sh "$VOLUME_BASE_DIR"/* 2>/dev/null | sort -h || echo "No volumes initialized yet"
    else
        echo "Volume directory not initialized: $VOLUME_BASE_DIR"
    fi
    
    # Cache statistics
    echo -e "\n${YELLOW}Cache Statistics:${NC}"
    
    # NuGet cache
    if [ -d "$VOLUME_BASE_DIR/nuget-packages" ]; then
        local nuget_count=$(find "$VOLUME_BASE_DIR/nuget-packages" -name "*.nupkg" 2>/dev/null | wc -l)
        local nuget_size=$(du -sh "$VOLUME_BASE_DIR/nuget-packages" 2>/dev/null | cut -f1)
        echo "  NuGet packages: $nuget_count packages, $nuget_size"
    fi
    
    # VS Code extensions
    if [ -d "$VOLUME_BASE_DIR/vscode-server/extensions" ]; then
        local ext_count=$(ls -1 "$VOLUME_BASE_DIR/vscode-server/extensions" 2>/dev/null | wc -l)
        echo "  VS Code extensions: $ext_count installed"
    fi
}

# [TAG-PERF-007-CLEAN] Clean volumes (with confirmation)
clean_volumes() {
    echo -e "${YELLOW}⚠️ Warning: This will delete all cached data!${NC}"
    read -p "Are you sure you want to clean all volumes? (y/N) " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        return 1
    fi
    
    echo -e "${RED}🗑️ Cleaning volumes...${NC}"
    
    # Stop containers using volumes
    docker-compose -f .devcontainer/docker-compose.volumes.yml down
    
    # Remove Docker volumes
    docker volume rm $(docker volume ls -q --filter "name=${PROJECT_NAME}") 2>/dev/null || true
    
    # Clean host directories (preserve structure)
    if [ -d "$VOLUME_BASE_DIR" ]; then
        find "$VOLUME_BASE_DIR" -mindepth 2 -delete
        echo "✅ Volumes cleaned"
    fi
}

# [TAG-PERF-007-BACKUP] Backup volumes
backup_volumes() {
    local backup_dir="${1:-./devcontainer-backup-$(date +%Y%m%d-%H%M%S)}"
    
    echo -e "${BLUE}💾 Backing up volumes to: $backup_dir${NC}"
    
    mkdir -p "$backup_dir"
    
    # Backup configuration
    cp -r .devcontainer "$backup_dir/" 2>/dev/null || true
    
    # Backup volume data
    if [ -d "$VOLUME_BASE_DIR" ]; then
        echo "Backing up volume data (this may take a while)..."
        tar -czf "$backup_dir/volumes.tar.gz" -C "$VOLUME_BASE_DIR" . --checkpoint=1000 --checkpoint-action=echo="  %u files backed up"
        
        local size=$(du -sh "$backup_dir/volumes.tar.gz" | cut -f1)
        echo "✅ Backup complete: $backup_dir/volumes.tar.gz ($size)"
    else
        echo "⚠️ No volumes to backup"
    fi
}

# [TAG-PERF-007-RESTORE] Restore volumes
restore_volumes() {
    local backup_file="${1}"
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}❌ Backup file not found: $backup_file${NC}"
        return 1
    fi
    
    echo -e "${BLUE}📥 Restoring volumes from: $backup_file${NC}"
    
    # Initialize directories
    init_volumes
    
    # Extract backup
    tar -xzf "$backup_file" -C "$VOLUME_BASE_DIR" --checkpoint=1000 --checkpoint-action=echo="  %u files restored"
    
    echo "✅ Restore complete"
}

# [TAG-PERF-007-OPTIMIZE] Optimize volumes
optimize_volumes() {
    echo -e "${BLUE}🚀 Optimizing volumes...${NC}"
    
    # Remove old NuGet packages
    if [ -d "$VOLUME_BASE_DIR/nuget-packages" ]; then
        echo "Cleaning old NuGet packages..."
        find "$VOLUME_BASE_DIR/nuget-packages" -type f -mtime +30 -delete
    fi
    
    # Compact Docker volumes
    echo "Compacting Docker volumes..."
    docker volume prune -f
    
    # Clear temporary files
    echo "Clearing temporary files..."
    find "$VOLUME_BASE_DIR" -name "*.tmp" -o -name "*.temp" -o -name "*.log" -delete
    
    echo "✅ Optimization complete"
}

# Main menu
show_menu() {
    echo -e "${GREEN}DevContainer Volume Manager${NC}"
    echo "=============================="
    echo "1) Initialize volumes"
    echo "2) Check volume status"
    echo "3) Clean all volumes"
    echo "4) Backup volumes"
    echo "5) Restore volumes"
    echo "6) Optimize volumes"
    echo "0) Exit"
    echo
    read -p "Select option: " option
    
    case $option in
        1) init_volumes ;;
        2) check_volume_status ;;
        3) clean_volumes ;;
        4) 
            read -p "Backup directory name (or press Enter for default): " dir
            backup_volumes "$dir"
            ;;
        5)
            read -p "Backup file path: " file
            restore_volumes "$file"
            ;;
        6) optimize_volumes ;;
        0) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -eq 0 ]; then
        show_menu
    else
        case "$1" in
            init) init_volumes ;;
            status) check_volume_status ;;
            clean) clean_volumes ;;
            backup) backup_volumes "${2:-}" ;;
            restore) restore_volumes "${2:-}" ;;
            optimize) optimize_volumes ;;
            *) show_menu ;;
        esac
    fi
fi
````

#### Verification Tests
````bash
#!/bin/bash
# filepath: .devcontainer/tests/verify-volumes.sh
# [TAG-PERF-007-TEST]

set -euo pipefail

FAILED=0

echo "🧪 Testing volume persistence..."

# Test 1: Volume directories exist
echo -n "TEST-PERF-007-A: Volume directories initialized... "
if [ -d "${HOME}/.aspire-devcontainer" ]; then
    echo "✅ PASS"
else
    echo "❌ FAIL: Volume base directory not found"
    ((FAILED++))
fi

# Test 2: Docker volumes created
echo -n "TEST-PERF-007-B: Docker volumes created... "
VOLUME_COUNT=$(docker volume ls --filter "name=aspire" -q | wc -l)
if [ $VOLUME_COUNT -gt 0 ]; then
    echo "✅ PASS ($VOLUME_COUNT volumes)"
else
    echo "❌ FAIL: No Docker volumes found"
    ((FAILED++))
fi

# Test 3: Volume persistence across rebuilds
echo -n "TEST-PERF-007-C: Testing persistence... "
TEST_FILE="/home/vscode/.nuget/packages/test-$(date +%s).txt"
docker-compose -f .devcontainer/docker-compose.volumes.yml run --rm dev \
    bash -c "echo 'test' > $TEST_FILE && cat $TEST_FILE" >/dev/null 2>&1

# Restart container and check file exists
docker-compose -f .devcontainer/docker-compose.volumes.yml run --rm dev \
    bash -c "[ -f $TEST_FILE ] && echo 'exists'" | grep -q "exists"

if [ $? -eq 0 ]; then
    echo "✅ PASS"
else
    echo "❌ FAIL: Files not persisted"
    ((FAILED++))
fi

# Test 4: Performance of tmpfs volumes
echo -n "TEST-PERF-007-D: tmpfs volume performance... "
docker-compose -f .devcontainer/docker-compose.volumes.yml run --rm dev \
    bash -c "dd if=/dev/zero of=/workspaces/aspire/obj/test.bin bs=1M count=100 2>&1" | \
    grep -oE '[0-9.]+ [MG]B/s' | tail -1 | read SPEED

echo "✅ Write speed: ${SPEED:-N/A}"

# Summary
echo ""
if [ $FAILED -eq 0 ]; then
    echo "✅ All volume tests passed!"
else
    echo "❌ $FAILED volume tests failed"
    exit 1
fi
````

---

### [TAG-ARCH-001] REQ-ARCH-001: Modular Scripts Architecture
**Reference:** TECHNICAL_DEBT_REPORT.md#req-arch-001
**Priority:** P2 | **Sprint:** 1 | **Effort:** 3 days | **Owner:** Dev
**Technical Debt ID:** TD-011

#### Problem Statement
Monolithic scripts causing:
- Duplicated code across scripts
- No reusable components
- Difficult to test individual functions
- No error handling framework

#### Modular Script Architecture Implementation

````bash
#!/bin/bash
# filepath: .devcontainer/scripts/lib/core.sh
# [TAG-ARCH-001-CORE]
# Core library for all DevContainer scripts

set -euo pipefail

# ============================================
# [TAG-ARCH-001-CONSTANTS] Global Constants
# ============================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
readonly DEVCONTAINER_DIR="$PROJECT_ROOT/.devcontainer"
readonly LOG_DIR="/tmp/devcontainer-logs"
readonly METRICS_DIR="/tmp/devcontainer-metrics"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Log levels
readonly LOG_ERROR=1
readonly LOG_WARN=2
readonly LOG_INFO=3
readonly LOG_DEBUG=4
readonly LOG_TRACE=5

# Default log level
LOG_LEVEL="${LOG_LEVEL:-$LOG_INFO}"

# ============================================
# [TAG-ARCH-001-LOGGING] Logging Framework
# ============================================
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
    
    # Check if we should log this level
    if [ $level -gt $LOG_LEVEL ]; then
        return
    fi
    
    # Determine color and prefix
    local color=""
    local prefix=""
    case $level in
        $LOG_ERROR)
            color=$RED
            prefix="ERROR"
            ;;
        $LOG_WARN)
            color=$YELLOW
            prefix="WARN "
            ;;
        $LOG_INFO)
            color=$GREEN
            prefix="INFO "
            ;;
        $LOG_DEBUG)
            color=$BLUE
            prefix="DEBUG"
            ;;
        $LOG_TRACE)
            color=$MAGENTA
            prefix="TRACE"
            ;;
    esac
    
    # Output to console
    echo -e "${color}[$timestamp] [$prefix] [$caller] $message${NC}" >&2
    
    # Write to log file
    mkdir -p "$LOG_DIR"
    echo "[$timestamp] [$prefix] [$caller] $message" >> "$LOG_DIR/devcontainer.log"
}

log_error() { log $LOG_ERROR "$@"; }
log_warn()  { log $LOG_WARN "$@"; }
log_info()  { log $LOG_INFO "$@"; }
log_debug() { log $LOG_DEBUG "$@"; }
log_trace() { log $LOG_TRACE "$@"; }

# ============================================
# [TAG-ARCH-001-ERROR-HANDLING] Error Handling
# ============================================
error_handler() {
    local line_no=$1
    local bash_lineno=$2
    local last_command=$3
    local code=$4
    
    log_error "Command failed with exit code $code"
    log_error "  Command: $last_command"
    log_error "  Line: $line_no"
    log_error "  Function: ${FUNCNAME[1]}"
    log_error "  Script: ${BASH_SOURCE[1]}"
    
    # Generate error report
    generate_error_report "$code" "$last_command"
    
    exit $code
}

# Set error trap
trap 'error_handler $LINENO $BASH_LINENO "$BASH_COMMAND" $?' ERR

# ============================================
# [TAG-ARCH-001-METRICS] Metrics Collection
# ============================================
metric_start() {
    local metric_name="$1"
    local start_time=$(date +%s%N)
    
    # Store start time in temp file
    mkdir -p "$METRICS_DIR"
    echo "$start_time" > "$METRICS_DIR/${metric_name}.start"
    
    log_debug "Metric started: $metric_name"
}

metric_end() {
    local metric_name="$1"
    local status="${2:-success}"
    local metadata="${3:-}"
    
    local end_time=$(date +%s%N)
    local start_file="$METRICS_DIR/${metric_name}.start"
    
    if [ ! -f "$start_file" ]; then
        log_warn "Metric $metric_name was not started"
        return
    fi
    
    local start_time=$(cat "$start_file")
    local duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
    
    # Write metric
    local metric_file="$METRICS_DIR/metrics.jsonl"
    cat >> "$metric_file" <<EOF
{"timestamp":"$(date -Iseconds)","metric":"$metric_name","duration_ms":$duration,"status":"#!/bin/bash
# filepath: .devcontainer/scripts/lib/core.sh
# [TAG-ARCH-001-CORE]
# Core library for all DevContainer scripts

set -euo pipefail

# ============================================
# [TAG-ARCH-001-CONSTANTS] Global Constants
# ============================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
readonly DEVCONTAINER_DIR="$PROJECT_ROOT/.devcontainer"
readonly LOG_DIR="/tmp/devcontainer-logs"
readonly METRICS_DIR="/tmp/devcontainer-metrics"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Log levels
readonly LOG_ERROR=1
readonly LOG_WARN=2
readonly LOG_INFO=3
readonly LOG_DEBUG=4
readonly LOG_TRACE=5

# Default log level
LOG_LEVEL="${LOG_LEVEL:-$LOG_INFO}"

# ============================================
# [TAG-ARCH-001-LOGGING] Logging Framework
# ============================================
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
    
    # Check if we should log this level
    if [ $level -gt $LOG_LEVEL ]; then
        return
    fi
    
    # Determine color and prefix
    local color=""
    local prefix=""
    case $level in
        $LOG_ERROR)
            color=$RED
            prefix="ERROR"
            ;;
        $LOG_WARN)
            color=$YELLOW
            prefix="WARN "
            ;;
        $LOG_INFO)
            color=$GREEN
            prefix="INFO "
            ;;
        $LOG_DEBUG)
            color=$BLUE
            prefix="DEBUG"
            ;;
        $LOG_TRACE)
            color=$MAGENTA
            prefix="TRACE"
            ;;
    esac
    
    # Output to console
    echo -e "${color}[$timestamp] [$prefix] [$caller] $message${NC}" >&2
    
    # Write to log file
    mkdir -p "$LOG_DIR"
    echo "[$timestamp] [$prefix] [$caller] $message" >> "$LOG_DIR/devcontainer.log"
}

log_error() { log $LOG_ERROR "$@"; }
log_warn()  { log $LOG_WARN "$@"; }
log_info()  { log $LOG_INFO "$@"; }
log_debug() { log $LOG_DEBUG "$@"; }
log_trace() { log $LOG_TRACE "$@"; }

# ============================================
# [TAG-ARCH-001-ERROR-HANDLING] Error Handling
# ============================================
error_handler() {
    local line_no=$1
    local bash_lineno=$2
    local last_command=$3
    local code=$4
    
    log_error "Command failed with exit code $code"
    log_error "  Command: $last_command"
    log_error "  Line: $line_no"
    log_error "  Function: ${FUNCNAME[1]}"
    log_error "  Script: ${BASH_SOURCE[1]}"
    
    # Generate error report
    generate_error_report "$code" "$last_command"
    
    exit $code
}

# Set error trap
trap 'error_handler $LINENO $BASH_LINENO "$BASH_COMMAND" $?' ERR

# ============================================
# [TAG-ARCH-001-METRICS] Metrics Collection
# ============================================
metric_start() {
    local metric_name="$1"
    local start_time=$(date +%s%N)
    
    # Store start time in temp file
    mkdir -p "$METRICS_DIR"
    echo "$start_time" > "$METRICS_DIR/${metric_name}.start"
    
    log_debug "Metric started: $metric_name"
}

metric_end() {
    local metric_name="$1"
    local status="${2:-success}"
    local metadata="${3:-}"
    
    local end_time=$(date +%s%N)
    local start_file="$METRICS_DIR/${metric_name}.start"
    
    if [ ! -f "$start_file" ]; then
        log_warn "Metric $metric_name was not started"
        return
    fi
    
    local start_time=$(cat "$start_file")
    local duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
    
    # Write metric
    local metric_file="$METRICS_DIR/metrics.jsonl"
    cat >> "$metric_file" <<EOF
{"timestamp":"$(date -Iseconds)","metric":"$metric_name","duration_ms":$duration,"status":"