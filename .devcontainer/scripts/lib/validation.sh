#!/bin/bash
# validation.sh - Input validation utilities
# Single Responsibility: Validate user inputs and environment variables

set -euo pipefail

# Source required dependencies
SCRIPT_LIB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_LIB_DIR/colors.sh"

# Generic validation functions
is_empty() {
    [ -z "$1" ]
}

is_not_empty() {
    [ -n "$1" ]
}

# Environment variable validation
validate_required_var() {
    local var_name="$1"
    local var_value="$2"
    
    if is_empty "$var_value"; then
        print_error "$var_name cannot be empty"
        return 1
    fi
    return 0
}

validate_optional_var() {
    local var_name="$1"
    local var_value="$2"
    
    # Optional variables are always valid, but we can still format check
    if is_not_empty "$var_value"; then
        validate_var_format "$var_name" "$var_value"
    fi
}

# Format validation functions
validate_github_username() {
    local username="$1"
    
    if [[ ! "$username" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        print_error "Invalid GitHub username/organization format: $username"
        return 1
    fi
    return 0
}

validate_runner_token_format() {
    local token="$1"
    
    if [[ ! "$token" =~ ^[A-Z0-9]{20,}$ ]]; then
        print_warning "Runner token format may be incorrect"
        return 1
    fi
    return 0
}

validate_token_length() {
    local token_name="$1"
    local token="$2"
    local min_length="${3:-10}"
    
    if [ ${#token} -lt $min_length ]; then
        print_warning "$token_name appears too short (${#token} chars, expected at least $min_length)"
        return 1
    fi
    return 0
}

# Comprehensive variable format validation
validate_var_format() {
    local var_name="$1"
    local var_value="$2"
    
    case "$var_name" in
        "GITHUB_OWNER")
            validate_github_username "$var_value"
            ;;
        "GITHUB_RUNNER_TOKEN")
            validate_runner_token_format "$var_value" || true  # Warning only
            ;;
        "GH_PAT")
            validate_token_length "GitHub PAT" "$var_value" 20
            ;;
        "DOCKER_ACCESS_TOKEN")
            validate_token_length "Docker access token" "$var_value" 8
            ;;
        "DOCKER_USERNAME")
            # Docker usernames can contain lowercase letters, digits, and hyphens
            if [[ ! "$var_value" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$ ]]; then
                print_warning "Docker username format may be incorrect: $var_value"
            fi
            ;;
    esac
}

# Validation with user feedback
validate_input_interactive() {
    local var_name="$1"
    local var_value="$2"
    local is_required="${3:-true}"
    
    if [ "$is_required" = true ]; then
        validate_required_var "$var_name" "$var_value" || return 1
    fi
    
    if is_not_empty "$var_value"; then
        validate_var_format "$var_name" "$var_value"
    fi
    
    return 0
}

# Command availability checks
check_required_commands() {
    local -a missing_commands=()
    local -a commands=("$@")
    
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_commands[*]}"
        echo "Install the missing tools and re-run (e.g. apt/apt-get, package manager or include in devcontainer features)."
        return 1
    fi
    
    return 0
}

check_optional_commands() {
    local -A available_commands
    local -a commands=("$@")
    
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            available_commands["$cmd"]=true
        else
            available_commands["$cmd"]=false
            print_warning "'$cmd' not found. Some features may be limited."
        fi
    done
    
    # Return availability status via global associative array
    for cmd in "${!available_commands[@]}"; do
        declare -g "AVAILABLE_${cmd^^}"="${available_commands[$cmd]}"
    done
}