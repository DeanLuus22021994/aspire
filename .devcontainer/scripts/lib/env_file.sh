#!/bin/bash
# env_file.sh - Environment file operations
# Single Responsibility: Handle .env file creation, reading, writing, and management

set -euo pipefail

# Source required dependencies
SCRIPT_LIB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_LIB_DIR/colors.sh"
source "$SCRIPT_LIB_DIR/file_ops.sh"
source "$SCRIPT_LIB_DIR/validation.sh"

# Constants
readonly DEFAULT_ENV_FILE=".devcontainer/.env"
readonly ENV_EXAMPLE_FILE=".devcontainer/.env.example"
readonly GITIGNORE_FILE=".gitignore"

# Environment file path resolution
get_env_file_path() {
    local custom_path="${1:-}"
    if is_not_empty "$custom_path"; then
        echo "$custom_path"
    else
        echo "$DEFAULT_ENV_FILE"
    fi
}

# Create .env.example template
create_env_template() {
    local template_path="${1:-$ENV_EXAMPLE_FILE}"
    
    if file_exists "$template_path"; then
        print_info "Template already exists: $template_path"
        return 0
    fi
    
    local template_content
    template_content=$(cat << 'EOF'
# GitHub Actions Runner Environment Variables
# Copy this file to .devcontainer/.env and fill in your values
# DO NOT commit .env file to version control

# GitHub Personal Access Token with repo and workflow scopes
GH_PAT=

# GitHub username or organization name
GITHUB_OWNER=

# GitHub Actions runner registration token (expires after 1 hour)
GITHUB_RUNNER_TOKEN=

# Docker Hub access token
DOCKER_ACCESS_TOKEN=

# Docker Hub username
DOCKER_USERNAME=
EOF
)
    
    if write_file_safely "$template_path" "$template_content"; then
        print_success "Created .env.example template"
        return 0
    else
        print_error "Failed to create template: $template_path"
        return 1
    fi
}

# Read environment variables from file
load_env_file() {
    local env_file="$1"
    
    if ! file_exists "$env_file"; then
        print_error "Environment file not found: $env_file"
        return 1
    fi
    
    if ! file_readable "$env_file"; then
        print_error "Cannot read environment file: $env_file"
        return 1
    fi
    
    # Load variables using set -a/+a pattern
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
    
    print_success "Loaded environment from $env_file"
    return 0
}

# Write environment variables to file
write_env_file() {
    local env_file="$1"
    local gh_pat="$2"
    local github_owner="$3"
    local github_runner_token="$4"
    local docker_access_token="$5"
    local docker_username="$6"
    
    local env_content
    env_content=$(cat << EOF
# GitHub Actions Runner Environment Variables
# Created on $(date)
# WARNING: Do not commit this file to version control

GH_PAT=${gh_pat}
GITHUB_OWNER=${github_owner}
GITHUB_RUNNER_TOKEN=${github_runner_token}
DOCKER_ACCESS_TOKEN=${docker_access_token}
DOCKER_USERNAME=${docker_username}
EOF
)
    
    if write_file_safely "$env_file" "$env_content"; then
        set_secure_permissions "$env_file"
        print_success "Created $env_file with environment variables"
        return 0
    else
        print_error "Failed to write environment file: $env_file"
        return 1
    fi
}

# Check environment file status
check_env_file_status() {
    local env_file="${1:-$DEFAULT_ENV_FILE}"
    
    print_subheader "Environment File Check"
    
    if file_exists "$env_file"; then
        print_success "$env_file file exists"
        
        local perms
        perms=$(get_file_permissions "$env_file")
        if [ "$perms" = "600" ]; then
            print_success ".env file has secure permissions (600)"
        else
            print_warning ".env file permissions are $perms (recommend 600)"
        fi
        
        check_gitignore_entry "$env_file"
    else
        print_info "No $env_file file found"
        echo "  Run .devcontainer/setup-env.sh to create one"
    fi
}

# Ensure .env is in .gitignore
ensure_gitignore() {
    local env_file="$1"
    local gitignore_path="${2:-$GITIGNORE_FILE}"
    
    if ! file_exists "$gitignore_path"; then
        print_warning ".gitignore not found - remember to exclude $env_file from version control"
        return 1
    fi
    
    local env_pattern
    env_pattern=$(basename "$(dirname "$env_file")"/$(basename "$env_file"))
    
    if ! grep -q "^$env_pattern$" "$gitignore_path"; then
        {
            echo ""
            echo "# Environment configuration with secrets"
            echo "$env_pattern"
        } >> "$gitignore_path"
        print_success "Added $env_pattern to .gitignore"
    else
        print_info "$env_pattern already in .gitignore"
    fi
}

# Check if .env is in .gitignore
check_gitignore_entry() {
    local env_file="$1"
    local gitignore_path="${2:-$GITIGNORE_FILE}"
    
    if file_exists "$gitignore_path"; then
        local env_pattern
        env_pattern=$(basename "$(dirname "$env_file")"/$(basename "$env_file"))
        
        if grep -q "$env_pattern" "$gitignore_path"; then
            print_success ".env file is in .gitignore"
        else
            print_error ".env file is NOT in .gitignore - security risk!"
            return 1
        fi
    else
        print_warning ".gitignore not found"
        return 1
    fi
}

# Check if environment variable is set
check_env_var() {
    local var_name="$1"
    local is_secret="${2:-false}"
    local var_value="${!var_name:-}"
    
    if is_empty "$var_value"; then
        print_error "$var_name: NOT SET"
        return 1
    else
        if [ "$is_secret" = true ]; then
            print_success "$var_name: SET (length: ${#var_value})"
        else
            print_success "$var_name: $var_value"
        fi
        return 0
    fi
}

# Load and export environment variables from file
export_env_vars() {
    local env_file="$1"
    
    # Create a temporary file with export statements
    local temp_export_file
    temp_export_file=$(mktemp)
    
    # Process the env file to create export statements
    while IFS='=' read -r key value; do
        # Skip empty lines and comments
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Remove any quotes from value
        value=$(echo "$value" | sed 's/^["\x27]\|["\x27]$//g')
        
        echo "export $key='$value'" >> "$temp_export_file"
    done < "$env_file"
    
    # Source the export file
    # shellcheck source=/dev/null
    source "$temp_export_file"
    rm -f "$temp_export_file"
    
    print_success "Exported variables from $env_file"
}