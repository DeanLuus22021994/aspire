#!/bin/bash
# verify-env.sh - Verify environment configuration
# Single Responsibility: Comprehensively verify environment variables and integrations

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$SCRIPT_DIR/lib"

# Source required modules
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/validation.sh"
source "$LIB_DIR/env_file.sh"
source "$LIB_DIR/github_api.sh"
source "$LIB_DIR/docker_api.sh"

# Required and optional commands
readonly REQUIRED_COMMANDS=(curl stat)
readonly OPTIONAL_COMMANDS=(docker jq)

# Environment variables to check
readonly REQUIRED_ENV_VARS=(GH_PAT GITHUB_OWNER GITHUB_RUNNER_TOKEN DOCKER_ACCESS_TOKEN DOCKER_USERNAME)
readonly ASPIRE_ENV_VARS=(ASPIRE_ALLOW_UNSECURED_TRANSPORT DOTNET_DASHBOARD_OTLP_ENDPOINT_URL DOTNET_DASHBOARD_UNSECURED_ALLOW_ANONYMOUS)

# Check command availability
check_command_availability() {
    print_header "Environment Variables Verification"
    
    # Check required commands
    if ! check_required_commands "${REQUIRED_COMMANDS[@]}"; then
        exit 2
    fi
    
    # Check optional commands and set availability flags
    check_optional_commands "${OPTIONAL_COMMANDS[@]}"
}

# Verify required environment variables
verify_required_env_vars() {
    print_subheader "Required Environment Variables"
    
    local missing_vars=0
    
    for var in "${REQUIRED_ENV_VARS[@]}"; do
        case "$var" in
            GH_PAT|GITHUB_RUNNER_TOKEN|DOCKER_ACCESS_TOKEN)
                check_env_var "$var" true || missing_vars=$((missing_vars + 1))
                ;;
            *)
                check_env_var "$var" false || missing_vars=$((missing_vars + 1))
                ;;
        esac
    done
    
    return $missing_vars
}

# Verify additional Aspire environment variables
verify_aspire_env_vars() {
    print_subheader "Additional Aspire Environment Variables"
    
    for var in "${ASPIRE_ENV_VARS[@]}"; do
        check_env_var "$var" false || true  # Non-critical
    done
}

# Check development environment
check_development_environment() {
    print_subheader "Development Environment Check"
    
    # Check Aspire CLI in PATH
    if echo "$PATH" | grep -q "/workspaces/aspire/artifacts/bin/Aspire.Cli"; then
        print_success "Aspire CLI path is in PATH"
    else
        print_warning "Aspire CLI path not found in PATH"
    fi
    
    # Check if running in Aspire devcontainer
    if file_exists "/workspaces/aspire/.devcontainer/devcontainer.json"; then
        print_success "Running in Aspire devcontainer"
    else
        print_warning "Not detected as running in Aspire devcontainer"
    fi
}

# Main verification function
main() {
    local overall_status=0
    
    # Setup cleanup for Docker operations
    setup_docker_cleanup
    
    # Note: This script verifies the current environment state\n    # If you need to load environment variables first, run:\n    # source .devcontainer/.env && .devcontainer/verify-env.sh
    
    # Check command availability
    check_command_availability
    
    # Verify required environment variables
    verify_required_env_vars || overall_status=$?
    
    # Verify additional Aspire environment variables
    verify_aspire_env_vars
    
    # Check environment file status
    check_env_file_status
    
    # Perform API verifications\n    verify_github_token\n    verify_docker_credentials\n    validate_runner_token\n    verify_runner_registration
    
    # Check development environment
    check_development_environment
    
    # Print final status
    echo
    print_header "Verification Results"
    
    if [ $overall_status -eq 0 ]; then
        print_success "All required environment variables are set!"
        print_success "Non-destructive verification completed"
    else
        print_error "$overall_status required environment variable(s) missing"
        print_warning "Run: .devcontainer/setup-env.sh"
    fi
    
    return $overall_status
}

# Execute main function
main "$@"