#!/bin/bash
# init-env.sh - Initialize environment for devcontainer
# Single Responsibility: Initialize and load environment variables in devcontainer

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$SCRIPT_DIR/lib"

# Source required modules
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/file_ops.sh"
source "$LIB_DIR/env_file.sh"

# Constants
readonly ENV_FILE=".devcontainer/.env"

# Initialize environment
main() {
    local exit_code=0
    
    # Load environment file if it exists
    if file_exists "$ENV_FILE"; then
        print_info "Loading environment from $ENV_FILE"
        
        if load_env_file "$ENV_FILE"; then
            print_success "Environment variables loaded"
        else
            print_error "Failed to load environment from $ENV_FILE"
            exit_code=1
        fi
    else
        print_info "No .env file found at $ENV_FILE"
        echo "Run .devcontainer/setup-env.sh to create one"
    fi
    
    # Make scripts executable
    chmod +x .devcontainer/*.sh 2>/dev/null || true
    chmod +x .devcontainer/scripts/*.sh 2>/dev/null || true
    
    # Check and fix .gitignore
    if file_exists "$ENV_FILE"; then
        check_gitignore_entry "$ENV_FILE" || {
            print_warning ".devcontainer/.env is not in .gitignore!"
            echo "Add it to prevent committing secrets to version control"
        }
    fi
    
    # Fix permissions and ownership if possible
    if file_exists "$ENV_FILE"; then
        print_info "Securing environment file permissions..."
        
        # Try to set container ownership
        set_container_ownership "$ENV_FILE" || true
        
        # Ensure secure permissions
        set_secure_permissions "$ENV_FILE" || true
    fi
    
    return $exit_code
}

# Execute main function
main "$@"