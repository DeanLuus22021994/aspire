#!/bin/bash
# post-create-validation.sh - Validate environment after container creation
# Single Responsibility: Comprehensive validation of devcontainer setup

set -euo pipefail

# Source utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$SCRIPT_DIR/../lib"
source "$LIB_DIR/colors.sh" 2>/dev/null || true

print_header "Post-Create Validation"

# Track validation status
validation_failed=0

# Check .NET SDK installation
print_subheader "Validating .NET SDK"
if command -v dotnet >/dev/null 2>&1; then
    sdk_version=$(dotnet --version 2>/dev/null || echo "unknown")
    print_success ".NET SDK installed: $sdk_version"

    # Check if it matches global.json
    required_version=$(grep -A 1 '"version"' /workspaces/aspire/global.json | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+-[a-z]\+\.[0-9]\+\.[0-9]\+' || echo "")
    if [ "$sdk_version" = "$required_version" ]; then
        print_success "SDK version matches global.json: $required_version"
    else
        print_warning "SDK version ($sdk_version) differs from global.json ($required_version)"
        print_info "Local SDK may be installed during restore"
    fi
else
    print_error ".NET SDK not found in PATH"
    validation_failed=1
fi

# Check workspace structure
print_subheader "Validating Workspace Structure"
required_dirs=(
    "/workspaces/aspire"
    "/workspaces/aspire/.dotnet"
    "/workspace-cache/nuget"
    "/workspace-cache/artifacts"
)

for dir in "${required_dirs[@]}"; do
    if [ -d "$dir" ]; then
        print_success "Directory exists: $dir"
    else
        print_error "Directory missing: $dir"
        validation_failed=1
    fi
done

# Check critical files
print_subheader "Validating Critical Files"
critical_files=(
    "/workspaces/aspire/global.json"
    "/workspaces/aspire/restore.sh"
    "/workspaces/aspire/build.sh"
    "/workspaces/aspire/Aspire.slnx"
)

for file in "${critical_files[@]}"; do
    if [ -f "$file" ]; then
        print_success "File exists: $file"
    else
        print_error "File missing: $file"
        validation_failed=1
    fi
done

# Check script permissions
print_subheader "Validating Script Permissions"
if [ -x "/workspaces/aspire/restore.sh" ]; then
    print_success "restore.sh is executable"
else
    print_error "restore.sh is not executable"
    validation_failed=1
fi

if [ -x "/workspaces/aspire/build.sh" ]; then
    print_success "build.sh is executable"
else
    print_error "build.sh is not executable"
    validation_failed=1
fi

# Check volume mounts
print_subheader "Validating Volume Mounts"
if mount | grep -q "/workspace-cache/nuget"; then
    print_success "NuGet cache volume mounted"
else
    print_warning "NuGet cache may not be using volume mount"
fi

# Check environment variables
print_subheader "Validating Environment Variables"
required_env_vars=(
    "DOTNET_ROOT"
    "NUGET_PACKAGES"
    "DOTNET_CLI_TELEMETRY_OPTOUT"
)

for var in "${required_env_vars[@]}"; do
    if [ -n "${!var:-}" ]; then
        print_success "$var is set: ${!var}"
    else
        print_warning "$var is not set"
    fi
done

# Display cache statistics
print_subheader "Cache Statistics"
echo "NuGet cache size: $(du -sh /workspace-cache/nuget 2>/dev/null | cut -f1 || echo 'N/A')"
echo "Artifacts cache size: $(du -sh /workspace-cache/artifacts 2>/dev/null | cut -f1 || echo 'N/A')"
echo ".dotnet cache size: $(du -sh /workspace-cache/.dotnet 2>/dev/null | cut -f1 || echo 'N/A')"

# Display resource usage
print_subheader "Container Resource Usage"
if command -v free >/dev/null 2>&1; then
    echo "Memory usage:"
    free -h | head -2
fi

if command -v df >/dev/null 2>&1; then
    echo ""
    echo "Disk usage:"
    df -h /workspaces/aspire | head -2
fi

# Final status
echo ""
if [ $validation_failed -eq 0 ]; then
    print_success "All validation checks passed!"
    echo ""
    print_info "Next steps:"
    echo "  1. Run './build.sh' to build the project"
    echo "  2. Run tests: 'dotnet test tests/<Project>.Tests/<Project>.Tests.csproj'"
    echo "  3. Use VS Code tasks (Ctrl+Shift+P → 'Tasks: Run Task')"
else
    print_warning "Some validation checks failed"
    echo ""
    print_info "This may be normal if restore hasn't completed yet"
    print_info "Try running './restore.sh' manually if issues persist"
fi

# Always exit 0 to not block container creation
exit 0
