#!/bin/bash
# cleanup.sh - Clean up Docker bloat and unused resources

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_info() {
    echo -e "${GREEN}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Check if running with proper permissions
if ! docker ps > /dev/null 2>&1; then
    print_error "Cannot connect to Docker daemon"
    echo "Make sure Docker is running and you have permissions"
    exit 1
fi

print_header "Docker Disk Usage Analysis"
echo ""

# Show current usage
docker system df
echo ""

# Detailed breakdown
print_info "Current state:"
echo "  • Images: $(docker images -q | wc -l) total"
echo "  • Containers: $(docker ps -aq | wc -l) total ($(docker ps -q | wc -l) running)"
echo "  • Volumes: $(docker volume ls -q | wc -l) total"
echo "  • Build cache: $(docker system df | grep 'Build Cache' | awk '{print $4}')"
echo ""

# Identify cleanup targets
stopped_containers=$(docker ps -aq -f 'status=exited' | wc -l)
dangling_images=$(docker images -f 'dangling=true' -q | wc -l)
unused_volumes=$(docker volume ls -qf dangling=true | wc -l)

# Calculate reclaimable space
reclaimable_images=$(docker system df | grep Images | awk '{print $4, $5}')
reclaimable_containers=$(docker system df | grep Containers | awk '{print $4, $5}')
reclaimable_cache=$(docker system df | grep 'Build Cache' | awk '{print $4}')

print_header "Cleanup Opportunities"
echo ""

echo "Stopped containers: $stopped_containers"
echo "Dangling images: $dangling_images"
echo "Unused volumes: $unused_volumes"
echo ""

echo "Reclaimable space:"
echo "  • Images: $reclaimable_images"
echo "  • Containers: $reclaimable_containers"
echo "  • Build cache: $reclaimable_cache"
echo ""

# Interactive cleanup menu
print_header "Cleanup Options"
echo ""
echo "1. Remove stopped containers (${stopped_containers} containers)"
echo "2. Remove unused images (reclaimable: ${reclaimable_images})"
echo "3. Remove build cache (${reclaimable_cache})"
echo "4. Remove dangling volumes (${unused_volumes} volumes)"
echo "5. Clean old devcontainer images (keep current only)"
echo "6. Clean Python cache volumes"
echo "7. Full cleanup (all of the above - AGGRESSIVE)"
echo "8. Prune with confirmation (safer)"
echo "9. Show detailed breakdown"
echo "10. Exit"
echo ""

read -p "Select option (1-10): " choice

case $choice in
    1)
        print_header "Removing Stopped Containers"
        if [ "$stopped_containers" -gt 0 ]; then
            docker ps -aq -f 'status=exited' | xargs -r docker rm
            print_success "Removed $stopped_containers stopped containers"
        else
            print_info "No stopped containers to remove"
        fi
        ;;

    2)
        print_header "Removing Unused Images"
        docker image prune -a -f
        print_success "Unused images removed"
        ;;

    3)
        print_header "Removing Build Cache"
        docker builder prune -af
        print_success "Build cache cleared"
        ;;

    4)
        print_header "Removing Dangling Volumes"
        if [ "$unused_volumes" -gt 0 ]; then
            docker volume prune -f
            print_success "Removed $unused_volumes dangling volumes"
        else
            print_info "No dangling volumes to remove"
        fi
        ;;

    5)
        print_header "Cleaning Old DevContainer Images"
        # Get current container's image
        current_image=$(docker ps --filter "label=devcontainer.local_folder=/projects/aspire" --format '{{.Image}}' | head -n 1)

        if [ -z "$current_image" ]; then
            print_warning "No running devcontainer found"
            current_image="none"
        else
            print_info "Current image: $current_image"
        fi

        # Remove old vsc-aspire images except current
        old_images=$(docker images --filter "reference=vsc-aspire*" --format '{{.Repository}}:{{.Tag}}' | grep -v "$current_image" || true)

        if [ -n "$old_images" ]; then
            echo "$old_images" | while read img; do
                print_info "Removing old image: $img"
                docker rmi "$img" 2>/dev/null || print_warning "Could not remove $img (may be in use)"
            done
            print_success "Old devcontainer images cleaned"
        else
            print_info "No old devcontainer images to remove"
        fi
        ;;

    6)
        print_header "Cleaning Python Cache Volumes"
        echo ""

        # Show Python cache volumes
        print_info "Python cache volumes:"
        docker volume ls | grep -E "(python-binaries-cache|python-tools-cache)" || print_warning "No Python cache volumes found"

        echo ""

        # Get sizes
        if docker volume inspect python-binaries-cache >/dev/null 2>&1; then
            binaries_size=$(docker run --rm -v python-binaries-cache:/cache alpine du -sh /cache 2>/dev/null | cut -f1 || echo "unknown")
            print_info "Python binaries cache: $binaries_size"
        fi

        if docker volume inspect python-tools-cache >/dev/null 2>&1; then
            tools_size=$(docker run --rm -v python-tools-cache:/cache alpine du -sh /cache 2>/dev/null | cut -f1 || echo "unknown")
            print_info "Python tools cache: $tools_size"
        fi

        echo ""
        print_warning "Removing Python cache will cause next build to recompile Python from source (~4 min)"
        read -p "Remove Python cache volumes? (yes/no): " confirm

        if [ "$confirm" = "yes" ]; then
            # Stop any containers using these volumes
            containers=$(docker ps -aq --filter "volume=python-binaries-cache" --filter "volume=python-tools-cache")
            if [ -n "$containers" ]; then
                print_warning "Stopping containers using Python cache volumes..."
                echo "$containers" | xargs -r docker stop
            fi

            # Remove volumes
            docker volume rm python-binaries-cache 2>/dev/null && print_success "Removed python-binaries-cache" || print_info "python-binaries-cache not found"
            docker volume rm python-tools-cache 2>/dev/null && print_success "Removed python-tools-cache" || print_info "python-tools-cache not found"

            print_success "Python cache cleared"
            print_info "Next container rebuild will repopulate the cache"
        else
            print_info "Python cache cleanup cancelled"
        fi
        ;;

    7)
        print_header "Full Cleanup (AGGRESSIVE)"
        print_warning "This will remove:"
        echo "  • All stopped containers"
        echo "  • All unused images"
        echo "  • All build cache"
        echo "  • All dangling volumes"
        echo "  • Old devcontainer images"
        echo ""
        read -p "Are you sure? (yes/no): " confirm

        if [ "$confirm" = "yes" ]; then
            # Stop and remove non-running devcontainers
            docker ps -aq --filter "label=devcontainer.local_folder=/projects/aspire" --filter "status=exited" | xargs -r docker rm -f

            # Remove stopped containers
            docker ps -aq -f 'status=exited' | xargs -r docker rm

            # Clean old devcontainer images
            current_image=$(docker ps --filter "label=devcontainer.local_folder=/projects/aspire" --format '{{.Image}}' | head -n 1 || echo "none")
            docker images --filter "reference=vsc-aspire*" --format '{{.Repository}}:{{.Tag}}' | grep -v "$current_image" | xargs -r docker rmi 2>/dev/null || true

            # Remove unused images
            docker image prune -af

            # Remove build cache
            docker builder prune -af

            # Remove dangling volumes
            docker volume prune -f

            print_success "Full cleanup complete!"

            echo ""
            print_header "Space Reclaimed"
            docker system df
        else
            print_info "Cleanup cancelled"
        fi
        ;;

    8)
        print_header "Pruning with Confirmation"
        docker system prune --volumes
        print_success "Prune complete"
        ;;

    9)
        print_header "Detailed Breakdown"
        echo ""

        echo "--- Images ---"
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
        echo ""

        echo "--- Containers ---"
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Size}}"
        echo ""

        echo "--- Volumes ---"
        docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}"
        echo ""

        echo "--- Build Cache Details ---"
        docker buildx du
        ;;

    10)
        print_info "Exiting without changes"
        exit 0
        ;;

    *)
        print_error "Invalid option"
        exit 1
        ;;
esac

echo ""
print_header "Final Disk Usage"
docker system df
echo ""

print_success "Cleanup complete!"
echo ""
print_info "Tips for maintaining clean Docker environment:"
echo "  • Run this script periodically"
echo "  • Use 'docker system prune' for quick cleanup"
echo "  • Keep only necessary volumes"
echo "  • Remove old devcontainer images after rebuilds"
