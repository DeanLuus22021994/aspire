#!/bin/bash
# docker_api.sh - Docker API verification utilities
# Single Responsibility: Handle Docker registry authentication and verification

set -euo pipefail

# Source required dependencies
SCRIPT_LIB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_LIB_DIR/colors.sh"
source "$SCRIPT_LIB_DIR/validation.sh"

# Docker Hub API endpoints
readonly DOCKER_HUB_API="https://hub.docker.com/v2"
readonly DOCKER_HUB_USER_ENDPOINT="$DOCKER_HUB_API/user/"
readonly DOCKER_REGISTRY="docker.io"

# Global cleanup tracking
TEMP_DOCKER_CONFIG=""

# Cleanup function for temporary Docker config
cleanup_temp_docker_config() {
    if is_not_empty "$TEMP_DOCKER_CONFIG" && [ -d "$TEMP_DOCKER_CONFIG" ]; then
        rm -rf "$TEMP_DOCKER_CONFIG"
        TEMP_DOCKER_CONFIG=""
    fi
}

# Check if Docker CLI is available
is_docker_available() {
    command -v docker >/dev/null 2>&1
}

# Create temporary Docker config directory
create_temp_docker_config() {
    TEMP_DOCKER_CONFIG=$(mktemp -d)
    export DOCKER_CONFIG="$TEMP_DOCKER_CONFIG"
}

# Clean up and unset Docker config
reset_docker_config() {
    cleanup_temp_docker_config
    unset DOCKER_CONFIG 2>/dev/null || true
}

# Verify Docker Hub API authentication
verify_docker_hub_api() {
    local username="$1"
    local token="$2"
    
    local auth_string
    auth_string=$(echo -n "$username:$token" | base64)
    
    local api_response
    api_response=$(curl -s -H "Authorization: Basic $auth_string" "$DOCKER_HUB_USER_ENDPOINT" 2>/dev/null || echo "")
    
    if is_not_empty "$api_response" && echo "$api_response" | grep -q '"username"'; then
        print_success "Docker Hub API authentication successful"
        return 0
    else
        print_warning "Docker Hub API authentication inconclusive"
        return 1
    fi
}

# Test Docker CLI login (isolated)
test_docker_cli_login() {
    local username="$1"
    local token="$2"
    
    if ! is_docker_available; then
        print_warning "Docker CLI not available - skipping docker login test"
        return 1
    fi
    
    create_temp_docker_config
    
    local login_result=1
    if echo "$token" | docker --config "$TEMP_DOCKER_CONFIG" login --username "$username" --password-stdin "$DOCKER_REGISTRY" &>/dev/null; then
        print_success "Docker registry login successful (isolated test)"
        
        # Clean logout
        docker --config "$TEMP_DOCKER_CONFIG" logout "$DOCKER_REGISTRY" &>/dev/null || true
        login_result=0
    else
        print_warning "Docker login test inconclusive or failed (isolated)"
    fi
    
    reset_docker_config
    return $login_result
}

# Comprehensive Docker credentials verification
verify_docker_credentials() {
    local username="${1:-${DOCKER_USERNAME:-}}"
    local token="${2:-${DOCKER_ACCESS_TOKEN:-}}"
    
    if is_empty "$username" || is_empty "$token"; then
        print_warning "Docker credentials not set - skipping verification"
        return 0
    fi
    
    print_subheader "Docker Credentials Verification (non-destructive)"
    
    local api_success=1
    local cli_success=1
    
    # Test API authentication
    verify_docker_hub_api "$username" "$token" || api_success=0
    
    # Test CLI authentication if Docker is available
    if is_docker_available; then
        test_docker_cli_login "$username" "$token" || cli_success=0
    else
        print_warning "Docker CLI not available - skipping CLI login test"
    fi
    
    # Return success if either method succeeded
    if [ $api_success -eq 0 ] || [ $cli_success -eq 0 ]; then
        return 0
    else
        print_error "Docker credentials verification failed"
        return 1
    fi
}

# Validate Docker credentials format
validate_docker_credentials() {
    local username="${1:-${DOCKER_USERNAME:-}}"
    local token="${2:-${DOCKER_ACCESS_TOKEN:-}}"
    
    local validation_errors=0
    
    if is_not_empty "$username"; then
        validate_input_interactive "DOCKER_USERNAME" "$username" true || validation_errors=$((validation_errors + 1))
    fi
    
    if is_not_empty "$token"; then
        validate_input_interactive "DOCKER_ACCESS_TOKEN" "$token" true || validation_errors=$((validation_errors + 1))
    fi
    
    return $validation_errors
}

# Setup signal handler for cleanup
setup_docker_cleanup() {
    trap cleanup_temp_docker_config EXIT INT TERM
}