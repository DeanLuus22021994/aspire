#!/bin/bash
# setup-env.sh - Setup environment variables
# Single Responsibility: Interactive and non-interactive environment variable setup

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$SCRIPT_DIR/lib"

# Source required modules
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/file_ops.sh"
source "$LIB_DIR/validation.sh"
source "$LIB_DIR/env_file.sh"

# Script configuration
readonly ENV_FILE=".devcontainer/.env"
readonly ENV_EXAMPLE=".devcontainer/.env.example"
readonly BASHRC_BACKUP_PREFIX="$HOME/.bashrc.backup"

# Command line options
NON_INTERACTIVE=false
FROM_FILE=""
SKIP_BASHRC=false

# Environment variables
GH_PAT_INPUT=""
GITHUB_OWNER_INPUT=""
GITHUB_RUNNER_TOKEN_INPUT=""
DOCKER_ACCESS_TOKEN_INPUT=""
DOCKER_USERNAME_INPUT=""

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-interactive|-n)
                NON_INTERACTIVE=true
                shift
                ;;
            --from-file|-f)
                FROM_FILE="$2"
                NON_INTERACTIVE=true
                shift 2
                ;;
            --skip-bashrc)
                SKIP_BASHRC=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --non-interactive, -n    Run without prompts (requires --from-file)"
    echo "  --from-file FILE, -f     Load variables from file"
    echo "  --skip-bashrc           Don't modify ~/.bashrc"
    echo "  --help, -h              Show this help message"
}

# Interactive setup process
interactive_setup() {
    # Security warning
    print_warning "Security Notice:"
    echo "This script will create a .devcontainer/.env file with sensitive tokens"
    echo "The .env file approach is more secure than storing in ~/.bashrc"
    echo
    
    read -p "Continue with setup? (y/N): " proceed
    if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
        echo "Setup cancelled"
        exit 0
    fi
    
    print_subheader "Enter your environment variables"
    
    # GitHub PAT
    while true; do
        read -p "Enter GH_PAT (GitHub Personal Access Token): " -s GH_PAT_INPUT
        echo
        if validate_input_interactive "GH_PAT" "$GH_PAT_INPUT" true; then
            break
        fi
    done
    
    # GitHub Owner
    while true; do
        read -p "Enter GITHUB_OWNER (username or organization): " GITHUB_OWNER_INPUT
        if validate_input_interactive "GITHUB_OWNER" "$GITHUB_OWNER_INPUT" true; then
            break
        fi
    done
    
    # GitHub Runner Token (optional)
    read -p "Enter GITHUB_RUNNER_TOKEN (press Enter to skip): " -s GITHUB_RUNNER_TOKEN_INPUT
    echo
    validate_input_interactive "GITHUB_RUNNER_TOKEN" "$GITHUB_RUNNER_TOKEN_INPUT" false || true
    
    # Docker Access Token
    while true; do
        read -p "Enter DOCKER_ACCESS_TOKEN: " -s DOCKER_ACCESS_TOKEN_INPUT
        echo
        if validate_input_interactive "DOCKER_ACCESS_TOKEN" "$DOCKER_ACCESS_TOKEN_INPUT" true; then
            break
        fi
    done
    
    # Docker Username
    while true; do
        read -p "Enter DOCKER_USERNAME: " DOCKER_USERNAME_INPUT
        if validate_input_interactive "DOCKER_USERNAME" "$DOCKER_USERNAME_INPUT" true; then
            break
        fi
    done
}

# Load variables from file
load_variables_from_file() {
    local file="$1"
    
    if ! file_exists "$file"; then
        print_error "File not found: $file"
        return 1
    fi
    
    # Export variables from file
    export_env_vars "$file"
    
    # Extract values
    GH_PAT_INPUT="${GH_PAT:-}"
    GITHUB_OWNER_INPUT="${GITHUB_OWNER:-}"
    GITHUB_RUNNER_TOKEN_INPUT="${GITHUB_RUNNER_TOKEN:-}"
    DOCKER_ACCESS_TOKEN_INPUT="${DOCKER_ACCESS_TOKEN:-}"
    DOCKER_USERNAME_INPUT="${DOCKER_USERNAME:-}"
    
    print_success "Loaded variables from $file"
}

# Setup bashrc integration
setup_bashrc_integration() {
    if [ "$SKIP_BASHRC" = true ]; then
        return 0
    fi
    
    # Create backup if .bashrc exists
    if file_exists "$HOME/.bashrc"; then
        local backup_file
        backup_file="$BASHRC_BACKUP_PREFIX.$(date +%Y%m%d_%H%M%S)"
        
        if create_backup "$HOME/.bashrc" "$(basename "$backup_file" "$HOME/.bashrc")"; then
            print_success "Created backup: $backup_file"
        fi
    fi
    
    # Add source line if not already present
    if ! grep -q "source.*\.devcontainer/\.env" "$HOME/.bashrc" 2>/dev/null; then
        {
            echo ""
            echo "# Source GitHub Actions environment (added by setup-env.sh)"
            echo "[ -f $ENV_FILE ] && set -a && source $ENV_FILE && set +a"
        } >> "$HOME/.bashrc"
        
        print_success "Added source command to ~/.bashrc (tokens stored in .env file)"
    else
        print_info "Source command already in ~/.bashrc"
    fi
}

# Display completion message
show_completion_message() {
    echo
    print_header "Environment setup complete!"
    
    echo "Next steps:"
    echo "1. Run 'source $ENV_FILE' to load variables in current session"
    echo "2. Run '.devcontainer/verify-env.sh' to verify setup"
    echo "3. Rebuild container to apply environment variables via --env-file"
    echo
    
    print_subheader "Security Notes"
    echo "- Tokens are stored in $ENV_FILE (not in ~/.bashrc)"
    echo "- File permissions set to 600 (owner read/write only)"
    echo "- Remember to rotate tokens periodically"
    echo "- Never commit .env file to version control"
}

# Main setup function
main() {
    parse_arguments "$@"
    
    print_header "GitHub Actions Runner Environment Setup"
    
    # Create template file
    create_env_template "$ENV_EXAMPLE"
    
    # Get environment variables
    if [ "$NON_INTERACTIVE" = true ]; then
        if is_empty "$FROM_FILE"; then
            print_error "Non-interactive mode requires --from-file option"
            exit 1
        fi
        load_variables_from_file "$FROM_FILE"
    else
        interactive_setup
    fi
    
    print_subheader "Setting up environment..."
    
    # Write environment file
    if write_env_file "$ENV_FILE" "$GH_PAT_INPUT" "$GITHUB_OWNER_INPUT" "$GITHUB_RUNNER_TOKEN_INPUT" "$DOCKER_ACCESS_TOKEN_INPUT" "$DOCKER_USERNAME_INPUT"; then
        print_success "Environment file created successfully"
    else
        print_error "Failed to create environment file"
        exit 1
    fi
    
    # Ensure .gitignore entry
    ensure_gitignore "$ENV_FILE"
    
    # Setup bashrc integration
    setup_bashrc_integration
    
    # Show completion message
    show_completion_message
}

# Execute main function
main "$@"