#!/bin/bash
# init-env.sh - Initialize environment for devcontainer
# Single Responsibility: Initialize and load environment variables in devcontainer
# This script should NEVER fail - all operations are best-effort

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$SCRIPT_DIR/../lib"

# Source required modules
source "$LIB_DIR/colors.sh" || exit 0
source "$LIB_DIR/file_ops.sh" || exit 0
source "$LIB_DIR/env_file.sh" || exit 0

# Constants
readonly ENV_FILE=".devcontainer/.env"
readonly ENV_EXAMPLE=".devcontainer/.env.example"

# Initialize environment
main() {
    print_info "Initializing devcontainer environment (non-blocking mode)"

    # Make scripts executable (best-effort)
    chmod +x .devcontainer/*.sh 2>/dev/null || true
    chmod +x .devcontainer/scripts/*.sh 2>/dev/null || true
    chmod +x .devcontainer/scripts/lib/*.sh 2>/dev/null || true

    # Check if .env exists
    if ! file_exists "$ENV_FILE"; then
        print_info "No .env file found at $ENV_FILE"

        # Try to create from example
        if file_exists "$ENV_EXAMPLE"; then
            print_info "Creating placeholder .env from .env.example"
            cp "$ENV_EXAMPLE" "$ENV_FILE" 2>/dev/null || {
                print_warning "Could not create .env from example - this is optional"
                return 0
            }
        else
            print_info "Creating minimal placeholder .env"
            echo "# Placeholder .env - run .devcontainer/scripts/setup-env.sh to configure" > "$ENV_FILE" 2>/dev/null || {
                print_warning "Could not create .env - this is optional"
                return 0
            }
        fi
    fi

    # Ensure .env is in .gitignore (best-effort)
    if file_exists "$ENV_FILE"; then
        ensure_gitignore "$ENV_FILE" 2>/dev/null || print_info ".env may not be in .gitignore yet"
    fi

    # Try to fix permissions (best-effort, expected to fail on bind mounts)
    if file_exists "$ENV_FILE"; then
        print_info "Attempting to secure environment file permissions..."

        # These are expected to fail on bind-mounted files - that's OK
        set_container_ownership "$ENV_FILE" 2>/dev/null || print_info "Could not change ownership (likely bind-mounted from host)"
        set_secure_permissions "$ENV_FILE" 2>/dev/null || print_info "Could not set permissions to 600 (likely bind-mounted from host)"

        # Try to load if readable
        if file_readable "$ENV_FILE"; then
            print_info "Loading environment variables from $ENV_FILE"
            load_env_file "$ENV_FILE" 2>/dev/null || print_info "Could not load .env file - you may need to source it manually"
        else
            print_info "$ENV_FILE exists but is not readable in current context"
        fi
    fi

    print_success "Environment initialization complete (best-effort mode)"
    echo ""
    echo "Next steps:"
    echo "  1. Run: ./restore.sh    (if not already done)"
    echo "  2. Run: ./build.sh      (to build the project)"
    echo "  3. Run: .devcontainer/scripts/setup-env.sh  (to configure GitHub Actions integration)"
    echo ""

    return 0
}

# Execute main function - never fail
main "$@" || {
    echo "⚠ Warning: init-env.sh encountered an error but continuing..."
    exit 0
}
