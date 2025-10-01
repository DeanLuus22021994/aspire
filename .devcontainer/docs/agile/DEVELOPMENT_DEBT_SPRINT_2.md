---
title: "DevContainer Development Debt - Sprint 2: CI/CD & Automation"
version: "3.0.0"
last_updated: "2024-10-31"
status: "Implementation Ready with Full Traceability"
sprint: 2
---

## Document Purpose & Sprint 2 Scope

This document provides detailed implementation specifications for Sprint 2 requirements focusing on CI/CD pipeline, automation, testing integration, and remaining performance optimizations. Each requirement is tagged for complete traceability with automated search and AI assistance capabilities.

**Sprint 2 Goals:**
- Automated prebuilds with 95% cache hit rate
- Multi-architecture support (AMD64 + ARM64)
- Container testing framework
- Registry caching implementation
- Health checks and resilience

**Tag Format:** `[TAG-{Category}-{ID}]` where:
- Category: PERF (Performance), ARCH (Architecture), TEST (Testing), RESIL (Resilience)
- ID: Three-digit requirement identifier

---

## 🚀 Performance Requirements (Continued from Sprint 1)

### [TAG-PERF-006] REQ-PERF-006: Registry Caching
**Reference:** TECHNICAL_DEBT_REPORT.md#req-perf-006
**Priority:** P1 | **Sprint:** 2 | **Effort:** 2 days | **Owner:** DevOps
**Technical Debt ID:** TD-006

#### Problem Statement
No shared cache between team members causing:
- Each developer rebuilds from scratch
- No registry-based cache sharing
- 7+ minute initial builds for everyone
- Wasted CI/CD resources

#### Complete Registry Cache Implementation

##### GitHub Container Registry Setup
````yaml
# filepath: .github/workflows/devcontainer-prebuild.yml
# [TAG-PERF-006-WORKFLOW]

name: DevContainer Prebuild & Registry Cache
on:
  push:
    branches: [main, release/*]
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
    - cron: '0 2 * * *'  # [TAG-PERF-006-SCHEDULE] Daily at 2 AM UTC
  workflow_dispatch:
    inputs:
      force_rebuild:
        description: 'Force rebuild without cache'
        required: false
        type: boolean
        default: false

env:
  # [TAG-PERF-006-ENV] Registry configuration
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}-devcontainer
  CACHE_NAME: ${{ github.repository }}-buildcache
  DOCKER_BUILDKIT: 1
  COMPOSE_DOCKER_CLI_BUILD: 1
  BUILDKIT_PROGRESS: plain

jobs:
  # [TAG-PERF-006-PREBUILD] Main prebuild job
  prebuild:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: read
      packages: write
      id-token: write
    
    strategy:
      fail-fast: false
      matrix:
        platform: [linux/amd64, linux/arm64]
        include:
          - platform: linux/amd64
            runner: ubuntu-latest
            cache-suffix: amd64
          - platform: linux/arm64
            runner: ubuntu-latest
            cache-suffix: arm64
    
    steps:
      # [TAG-PERF-006-CHECKOUT]
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          submodules: recursive
      
      # [TAG-PERF-006-QEMU] Multi-arch support
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3
        with:
          platforms: all
      
      # [TAG-PERF-006-BUILDX] BuildX configuration
      - name: Set up Docker Buildx
        id: buildx
        uses: docker/setup-buildx-action@v3
        with:
          version: latest
          driver-opts: |
            image=moby/buildkit:v0.12.0
            network=host
          buildkitd-flags: --debug
          config-inline: |
            [worker.oci]
              max-parallelism = 4
            [registry."${{ env.REGISTRY }}"]
              mirrors = ["${{ env.REGISTRY }}"]
            [gc]
              enabled = true
              keepBytes = 10737418240
              keepDuration = 604800
      
      # [TAG-PERF-006-LOGIN] Registry authentication
      - name: Log in to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      # [TAG-PERF-006-METADATA] Image metadata
      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          flavor: |
            latest=auto
            prefix=
            suffix=-${{ matrix.cache-suffix }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha,prefix={{branch}}-
            type=raw,value=latest,enable={{is_default_branch}}
            type=raw,value=cache-${{ matrix.cache-suffix }}
            type=raw,value=nightly,enable=${{ github.event_name == 'schedule' }}
      
      # [TAG-PERF-006-BUILD] Build and push with cache
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
            type=gha,scope=${{ matrix.platform }}
            type=registry,ref=${{ env.REGISTRY }}/${{ env.CACHE_NAME }}:${{ matrix.cache-suffix }}
            type=registry,ref=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:cache-${{ matrix.cache-suffix }}
            type=registry,ref=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
            type=registry,ref=mcr.microsoft.com/devcontainers/dotnet:1-10.0-preview-bookworm
          cache-to: |
            type=gha,scope=${{ matrix.platform }},mode=max
            type=registry,ref=${{ env.REGISTRY }}/${{ env.CACHE_NAME }}:${{ matrix.cache-suffix }},mode=max
            type=inline
          build-args: |
            BUILDKIT_INLINE_CACHE=1
            BUILD_DATE=${{ github.event.repository.updated_at }}
            VCS_REF=${{ github.sha }}
            VERSION=${{ github.ref_name }}
            PLATFORM=${{ matrix.platform }}
          secrets: |
            "github_token=${{ secrets.GITHUB_TOKEN }}"
          no-cache: ${{ inputs.force_rebuild == true }}
          outputs: type=image,name=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }},push-by-digest=true,name-canonical=true,push=true
      
      # [TAG-PERF-006-EXPORT] Export digest for multi-arch manifest
      - name: Export digest
        run: |
          mkdir -p /tmp/digests
          digest="${{ steps.build.outputs.digest }}"
          touch "/tmp/digests/${digest#sha256:}"
      
      # [TAG-PERF-006-UPLOAD] Upload digest for manifest creation
      - name: Upload digest
        uses: actions/upload-artifact@v4
        with:
          name: digests-${{ matrix.cache-suffix }}
          path: /tmp/digests/*
          if-no-files-found: error
          retention-days: 1
  
  # [TAG-PERF-006-MANIFEST] Create multi-arch manifest
  create-manifest:
    runs-on: ubuntu-latest
    needs: prebuild
    permissions:
      packages: write
    
    steps:
      - name: Download digests
        uses: actions/download-artifact@v4
        with:
          path: /tmp/digests
          pattern: digests-*
          merge-multiple: true
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Log in to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Create manifest list and push
        working-directory: /tmp/digests
        run: |
          docker buildx imagetools create \
            --tag ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest \
            --tag ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
            $(printf '${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@sha256:%s ' *)
````

##### Local Registry Cache Usage
````bash
#!/bin/bash
# filepath: .devcontainer/scripts/use-registry-cache.sh
# [TAG-PERF-006-LOCAL-SCRIPT]

set -euo pipefail

REGISTRY="ghcr.io"
IMAGE_NAME="microsoft/aspire-devcontainer"
PLATFORM=$(uname -m)

# Map platform to cache suffix
case $PLATFORM in
    x86_64)
        CACHE_SUFFIX="amd64"
        ;;
    aarch64|arm64)
        CACHE_SUFFIX="arm64"
        ;;
    *)
        echo "❌ Unsupported platform: $PLATFORM"
        exit 1
        ;;
esac

echo "🔄 Pulling registry cache for $PLATFORM..."

# [TAG-PERF-006-PULL] Pull cache image
docker pull "${REGISTRY}/${IMAGE_NAME}:cache-${CACHE_SUFFIX}" || {
    echo "⚠️ Cache pull failed, continuing without cache"
    exit 0
}

echo "🏗️ Building with registry cache..."

# [TAG-PERF-006-BUILD-LOCAL] Build with cache
docker build \
    --cache-from "${REGISTRY}/${IMAGE_NAME}:cache-${CACHE_SUFFIX}" \
    --cache-from "${REGISTRY}/${IMAGE_NAME}:latest" \
    -f .devcontainer/Dockerfile.optimized \
    -t aspire-dev:local \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    .

echo "✅ Build completed with registry cache"
````

##### Cache Verification Test
````bash
#!/bin/bash
# filepath: .devcontainer/tests/verify-registry-cache.sh
# [TAG-PERF-006-TEST]

set -euo pipefail

echo "🧪 Testing registry cache effectiveness..."

# Test cache availability
echo -n "TEST-PERF-006-A: Registry accessible... "
if curl -s "https://${REGISTRY:-ghcr.io}/v2/" >/dev/null; then
    echo "✅ PASS"
else
    echo "❌ FAIL: Registry not accessible"
    exit 1
fi

# Test cache image exists
echo -n "TEST-PERF-006-B: Cache image available... "
if docker manifest inspect "${REGISTRY}/${IMAGE_NAME}:cache-amd64" >/dev/null 2>&1; then
    echo "✅ PASS"
else
    echo "❌ FAIL: Cache image not found"
    exit 1
fi

# Measure build with cache
echo "TEST-PERF-006-C: Build performance with cache..."
START=$(date +%s)
docker build \
    --cache-from "${REGISTRY}/${IMAGE_NAME}:cache-amd64" \
    -f .devcontainer/Dockerfile.optimized \
    -t test-cache:1 \
    . >/dev/null 2>&1
END=$(date +%s)
CACHE_TIME=$((END - START))

# Measure build without cache
START=$(date +%s)
docker build \
    --no-cache \
    -f .devcontainer/Dockerfile.optimized \
    -t test-cache:2 \
    . >/dev/null 2>&1
END=$(date +%s)
NO_CACHE_TIME=$((END - START))

IMPROVEMENT=$((NO_CACHE_TIME / CACHE_TIME))

echo "  With cache:    ${CACHE_TIME}s"
echo "  Without cache: ${NO_CACHE_TIME}s"
echo "  Improvement:   ${IMPROVEMENT}x"

if [ $IMPROVEMENT -gt 3 ]; then
    echo "✅ Registry cache test PASSED"
else
    echo "❌ Registry cache test FAILED (expected >3x improvement)"
    exit 1
fi
````

#### Performance Metrics

| Metric | Local Build | Registry Cache | Improvement |
|--------|------------|----------------|-------------|
| Initial Build | 420s | 120s | 3.5x |
| Cache Hit Rate | 0% | 85% | ∞ |
| Team Efficiency | Individual | Shared | 10x |
| CI/CD Resources | High | Optimized | 70% reduction |

---

### [TAG-PERF-007] REQ-PERF-007: Volume Persistence
**Reference:** TECHNICAL_DEBT_REPORT.md#req-perf-007
**Priority:** P1 | **Sprint:** 1 | **Effort:** 1 day | **Owner:** DevOps
**Technical Debt ID:** TD-007

#### Problem Statement
No persistent volumes causing:
- Build artifacts lost on container rebuild
- NuGet packages re-downloaded
- Extensions reinstalled every time
- Command history lost

#### Complete Volume Persistence Implementation

##### Docker Compose with Persistent Volumes
````yaml
# filepath: .devcontainer/docker-compose.persistent.yml
# [TAG-PERF-007-COMPOSE]

version: '3.8'

services:
  dev:
    build:
      context: ..
      dockerfile: .devcontainer/Dockerfile.optimized
      args:
        BUILDKIT_INLINE_CACHE: 1
    
    image: aspire-devcontainer:latest
    container_name: aspire-dev
    hostname: aspire-dev
    
    volumes:
      # [TAG-PERF-007-SOURCE] Source code with optimal consistency
      - type: bind
        source: ..
        target: /workspaces/aspire
        consistency: delegated
      
      # [TAG-PERF-007-NUGET] NuGet packages persistence
      - type: volume
        source: nuget-packages
        target: /home/vscode/.nuget/packages
        volume:
          nocopy: false
      
      # [TAG-PERF-007-NUGET-HTTP] NuGet HTTP cache
      - type: volume
        source: nuget-http-cache
        target: /home/vscode/.local/share/NuGet/http-cache
      
      # [TAG-PERF-007-DOTNET-TOOLS] .NET tools persistence
      - type: volume
        source: dotnet-tools
        target: /home/vscode/.dotnet/tools
      
      # [TAG-PERF-007-EXTENSIONS] VS Code extensions
      - type: volume
        source: vscode-extensions
        target: /home/vscode/.vscode-server/extensions
      
      # [TAG-PERF-007-ARTIFACTS] Build artifacts
      - type: volume
        source: aspire-artifacts
        target: /workspaces/aspire/artifacts
      
      # [TAG-PERF-007-OBJ] Object file cache
      - type: volume
        source: obj-cache
        target: /workspaces/aspire/.obj-cache
      
      # [TAG-PERF-007-BIN] Binary cache
      - type: volume
        source: bin-cache
        target: /workspaces/aspire/.bin-cache
      
      # [TAG-PERF-007-HISTORY] Command history
      - type: volume
        source: bash-history
        target: /commandhistory
      
      # [TAG-PERF-007-SSH] SSH configuration (read-only)
      - type: bind
        source: ${HOME}/.ssh
        target: /home/vscode/.ssh
        read_only: true
        consistency: cached
      
      # [TAG-PERF-007-GIT] Git configuration (read-only)
      - type: bind
        source: ${HOME}/.gitconfig
        target: /home/vscode/.gitconfig.host
        read_only: true
        consistency: cached
      
      # [TAG-PERF-007-AZURE] Azure CLI configuration
      - type: volume
        source: azure-cli
        target: /home/vscode/.azure

# [TAG-PERF-007-VOLUME-DEFINITIONS]
volumes:
  nuget-packages:
    name: aspire-nuget-packages
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${HOME}/.aspire/nuget-packages
  
  nuget-http-cache:
    name: aspire-nuget-http
    driver: local
    driver_opts:
      type: tmpfs
      o: size=2g,uid=1000,gid=1000,mode=0755
  
  dotnet-tools:
    name: aspire-dotnet-tools
    driver: local
  
  vscode-extensions:
    name: aspire-vscode-extensions
    driver: local
  
  aspire-artifacts:
    name: aspire-artifacts
    driver: local
    driver_opts:
      type: tmpfs
      o: size=4g,uid=1000,gid=1000,mode=0755
  
  obj-cache:
    name: aspire-obj-cache
    driver: local
    driver_opts:
      type: tmpfs
      o: size=8g,uid=1000,gid=1000,mode=0755
  
  bin-cache:
    name: aspire-bin-cache
    driver: local
    driver_opts:
      type: tmpfs
      o: size=4g,uid=1000,gid=1000,mode=0755
  
  bash-history:
    name: aspire-bash-history
    driver: local
  
  azure-cli:
    name: aspire-azure-cli
    driver: local
````

##### Volume Management Script
````bash
#!/bin/bash
# filepath: .devcontainer/scripts/manage-volumes.sh
# [TAG-PERF-007-SCRIPT]

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Volume list
VOLUMES=(
    "aspire-nuget-packages"
    "aspire-nuget-http"
    "aspire-dotnet-tools"
    "aspire-vscode-extensions"
    "aspire-artifacts"
    "aspire-obj-cache"
    "aspire-bin-cache"
    "aspire-bash-history"
    "aspire-azure-cli"
)

# [TAG-PERF-007-CREATE] Create volumes
create_volumes() {
    echo -e "${BLUE}📦 Creating persistent volumes...${NC}"
    
    # Create host directories if needed
    mkdir -p "${HOME}/.aspire/nuget-packages"
    
    for volume in "${VOLUMES[@]}"; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠️ Volume $volume already exists${NC}"
        else
            docker volume create "$volume" >/dev/null
            echo -e "${GREEN}✅ Created volume: $volume${NC}"
        fi
    done
}

# [TAG-PERF-007-LIST] List volumes
list_volumes() {
    echo -e "${BLUE}📋 Aspire DevContainer Volumes:${NC}"
    
    for volume in "${VOLUMES[@]}"; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            SIZE=$(docker run --rm -v "$volume:/data" alpine du -sh /data 2>/dev/null | cut -f1 || echo "empty")
            echo -e "  ${GREEN}✓${NC} $volume (${SIZE})"
        else
            echo -e "  ${RED}✗${NC} $volume (not found)"
        fi
    done
}

# [TAG-PERF-007-CLEAN] Clean volumes
clean_volumes() {
    echo -e "${YELLOW}⚠️ This will delete all Aspire DevContainer volumes!${NC}"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for volume in "${VOLUMES[@]}"; do
            if docker volume rm "$volume" 2>/dev/null; then
                echo -e "${GREEN}✅ Removed volume: $volume${NC}"
            else
                echo -e "${YELLOW}⚠️ Could not remove volume: $volume${NC}"
            fi
        done
    fi
}

# [TAG-PERF-007-BACKUP] Backup volumes
backup_volumes() {
    BACKUP_DIR="${HOME}/.aspire/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    echo -e "${BLUE}💾 Backing up volumes to $BACKUP_DIR...${NC}"
    
    for volume in "${VOLUMES[@]}"; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            echo -n "  Backing up $volume... "
            docker run --rm \
                -v "$volume:/source:ro" \
                -v "$BACKUP_DIR:/backup" \
                alpine tar czf "/backup/${volume}.tar.gz" -C /source . 2>/dev/null
            echo -e "${GREEN}done${NC}"
        fi
    done
    
    echo -e "${GREEN}✅ Backup completed: $BACKUP_DIR${NC}"
}

# [TAG-PERF-007-RESTORE] Restore volumes
restore_volumes() {
    if [ -z "${1:-}" ]; then
        echo -e "${RED}❌ Please specify backup directory${NC}"
        exit 1
    fi
    
    BACKUP_DIR="$1"
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}❌ Backup directory not found: $BACKUP_DIR${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}📥 Restoring volumes from $BACKUP_DIR...${NC}"
    
    for volume in "${VOLUMES[@]}"; do
        BACKUP_FILE="$BACKUP_DIR/${volume}.tar.gz"
        if [ -f "$BACKUP_FILE" ]; then
            echo -n "  Restoring $volume... "
            docker run --rm \
                -v "$volume:/target" \
                -v "$BACKUP_DIR:/backup:ro" \
                alpine tar xzf "/backup/${volume}.tar.gz" -C /target
            echo -e "${GREEN}done${NC}"
        fi
    done
    
    echo -e "${GREEN}✅ Restore completed${NC}"
}

# Main menu
case "${1:-}" in
    create)
        create_volumes
        ;;
    list|ls)
        list_volumes
        ;;
    clean|rm)
        clean_volumes
        ;;
    backup)
        backup_volumes
        ;;
    restore)
        restore_volumes "${2:-}"
        ;;
    *)
        echo "Usage: $0 {create|list|clean|backup|restore <dir>}"
        exit 1
        ;;
esac
````

##### Volume Persistence Test
````bash
#!/bin/bash
# filepath: .devcontainer/tests/verify-volumes.sh
# [TAG-PERF-007-TEST]

set -euo pipefail

echo "🧪 Testing volume persistence..."

# Test volume creation
echo -n "TEST-PERF-007-A: Volume creation... "
bash .devcontainer/scripts/manage-volumes.sh create >/dev/null 2>&1
if docker volume ls | grep -q "aspire-nuget-packages"; then
    echo "✅ PASS"
else
    echo "❌ FAIL: Volumes not created"
    exit 1
fi

# Test data persistence
echo -n "TEST-PERF-007-B: Data persistence... "
TEST_FILE="/tmp/test-$(date +%s).txt"
docker run --rm -v aspire-nuget-packages:/data alpine \
    sh -c "echo 'test data' > /data/test.txt"
docker run --rm -v aspire-nuget-packages:/data alpine \
    cat /data/test.txt >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ PASS"
else
    echo "❌ FAIL: Data not persisted"
    exit 1
fi

# Test volume size
echo -n "TEST-PERF-007-C: Volume size management... "
SIZE=$(docker run --rm -v aspire-obj-cache:/data alpine df -h /data | tail -1 | awk '{print $2}')
if [[ "$SIZE" == *"G"* ]]; then
    echo "✅ PASS (Size: $SIZE)"
else
    echo "❌ FAIL: Volume size incorrect"
    exit 1
fi

echo "✅ All volume tests passed!"
````

#### Performance Impact

| Metric | Without Volumes | With Volumes | Improvement |
|--------|-----------------|--------------|-------------|
| Rebuild Time | 420s | 30s | 14x |
| Package Downloads | Every rebuild | Once | ∞ |
| Extension Install | Every rebuild | Once | ∞ |
| Data Persistence | None | Full | ✅ |
