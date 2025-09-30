#!/bin/bash
# filepath: .devcontainer/setup-env.sh

set -euo pipefail

# Script configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"
BASHRC_BACKUP="${HOME}/.bashrc.backup.$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command-line arguments
NON_INTERACTIVE=false
FROM_FILE=""
SKIP_BASHRC=false

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
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --non-interactive, -n    Run without prompts (requires --from-file)"
            echo "  --from-file FILE, -f     Load variables from file"
            echo "  --skip-bashrc           Don't modify ~/.bashrc"
            echo "  --help, -h              Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  GitHub Actions Runner Environment Setup${NC}"
echo -e "${BLUE}=========================================${NC}"
echo

# Function to validate input
validate_input() {
    local var_name=$1
    local var_value=$2
    local is_required=${3:-true}
    
    if [ "$is_required" = true ] && [ -z "$var_value" ]; then
        echo -e "${RED}Error: $var_name cannot be empty${NC}"
        return 1
    fi
    
    # Additional validation for specific variables
    case "$var_name" in
        "GITHUB_OWNER")
            if [ ! -z "$var_value" ] && [[ ! "$var_value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
                echo -e "${RED}Error: Invalid GitHub username/organization format${NC}"
                return 1
            fi
            ;;
        "GITHUB_RUNNER_TOKEN")
            if [ ! -z "$var_value" ] && [[ ! "$var_value" =~ ^[A-Z0-9]{20,}$ ]]; then
                echo -e "${YELLOW}Warning: Runner token format may be incorrect${NC}"
            fi
            ;;
    esac
    
    return 0
}

# Function to backup .bashrc
backup_bashrc() {
    if [ -f ~/.bashrc ] && [ "$SKIP_BASHRC" = false ]; then
        cp ~/.bashrc "$BASHRC_BACKUP"
        echo -e "${GREEN}✓${NC} Created backup: $BASHRC_BACKUP"
    fi
}

# Function to create .env template if needed
create_env_template() {
    if [ ! -f "$ENV_EXAMPLE" ]; then
        cat > "$ENV_EXAMPLE" << 'EOF'
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
        echo -e "${GREEN}✓${NC} Created .env.example template"
    fi
}

# Function to load variables from file
load_from_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: File not found: $file${NC}"
        return 1
    fi
    
    # Source the file in a subshell to capture variables
    (
        set -a
        source "$file"
        set +a
        
        # Export to parent shell
        echo "export GH_PAT='$GH_PAT'"
        echo "export GITHUB_OWNER='$GITHUB_OWNER'"
        echo "export GITHUB_RUNNER_TOKEN='$GITHUB_RUNNER_TOKEN'"
        echo "export DOCKER_ACCESS_TOKEN='$DOCKER_ACCESS_TOKEN'"
        echo "export DOCKER_USERNAME='$DOCKER_USERNAME'"
    ) > /tmp/env_exports.sh
    
    source /tmp/env_exports.sh
    rm -f /tmp/env_exports.sh
    
    echo -e "${GREEN}✓${NC} Loaded variables from $file"
}

# Interactive mode
interactive_setup() {
    # Security warning
    echo -e "${YELLOW}⚠ Security Notice:${NC}"
    echo "This script will create a .devcontainer/.env file with sensitive tokens"
    echo "The .env file approach is more secure than storing in ~/.bashrc"
    echo
    read -p "Continue with setup? (y/N): " proceed
    if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
        echo "Setup cancelled"
        exit 0
    fi

    echo
    echo -e "${BLUE}Enter your environment variables:${NC}"

    # GitHub PAT
    while true; do
        read -p "Enter GH_PAT (GitHub Personal Access Token): " -s GH_PAT_INPUT
        echo
        if validate_input "GH_PAT" "$GH_PAT_INPUT"; then
            break
        fi
    done

    # GitHub Owner
    while true; do
        read -p "Enter GITHUB_OWNER (username or organization): " GITHUB_OWNER_INPUT
        if validate_input "GITHUB_OWNER" "$GITHUB_OWNER_INPUT"; then
            break
        fi
    done

    # GitHub Runner Token
    read -p "Enter GITHUB_RUNNER_TOKEN (press Enter to skip): " -s GITHUB_RUNNER_TOKEN_INPUT
    echo
    validate_input "GITHUB_RUNNER_TOKEN" "$GITHUB_RUNNER_TOKEN_INPUT" false

    # Docker Access Token
    while true; do
        read -p "Enter DOCKER_ACCESS_TOKEN: " -s DOCKER_ACCESS_TOKEN_INPUT
        echo
        if validate_input "DOCKER_ACCESS_TOKEN" "$DOCKER_ACCESS_TOKEN_INPUT"; then
            break
        fi
    done

    # Docker Username
    while true; do
        read -p "Enter DOCKER_USERNAME: " DOCKER_USERNAME_INPUT
        if validate_input "DOCKER_USERNAME" "$DOCKER_USERNAME_INPUT"; then
            break
        fi
    done

    # Set variables
    export GH_PAT="$GH_PAT_INPUT"
    export GITHUB_OWNER="$GITHUB_OWNER_INPUT"
    export GITHUB_RUNNER_TOKEN="$GITHUB_RUNNER_TOKEN_INPUT"
    export DOCKER_ACCESS_TOKEN="$DOCKER_ACCESS_TOKEN_INPUT"
    export DOCKER_USERNAME="$DOCKER_USERNAME_INPUT"
}

# Main logic
create_env_template

if [ "$NON_INTERACTIVE" = true ]; then
    if [ -z "$FROM_FILE" ]; then
        echo -e "${RED}Error: Non-interactive mode requires --from-file option${NC}"
        exit 1
    fi
    load_from_file "$FROM_FILE"
else
    interactive_setup
fi

echo
echo -e "${BLUE}Setting up environment...${NC}"

# Create .env file
cat > "$ENV_FILE" << EOF
# GitHub Actions Runner Environment Variables
# Created on $(date)
# WARNING: Do not commit this file to version control

GH_PAT=${GH_PAT}
GITHUB_OWNER=${GITHUB_OWNER}
GITHUB_RUNNER_TOKEN=${GITHUB_RUNNER_TOKEN}
DOCKER_ACCESS_TOKEN=${DOCKER_ACCESS_TOKEN}
DOCKER_USERNAME=${DOCKER_USERNAME}
EOF

chmod 600 "$ENV_FILE"
echo -e "${GREEN}✓${NC} Created $ENV_FILE with restrictive permissions (600)"

# Add to .gitignore if not present
GITIGNORE_FILE="${SCRIPT_DIR}/../.gitignore"
if [ -f "$GITIGNORE_FILE" ]; then
    if ! grep -q "^.devcontainer/.env$" "$GITIGNORE_FILE"; then
        echo "" >> "$GITIGNORE_FILE"
        echo "# Environment configuration with secrets" >> "$GITIGNORE_FILE"
        echo ".devcontainer/.env" >> "$GITIGNORE_FILE"
        echo -e "${GREEN}✓${NC} Added .devcontainer/.env to .gitignore"
    fi
else
    echo -e "${YELLOW}⚠${NC} .gitignore not found - remember to exclude .devcontainer/.env from version control"
fi

# Optional: Add source line to .bashrc (not the actual tokens)
if [ "$SKIP_BASHRC" = false ]; then
    backup_bashrc
    
    # Check if source line already exists
    if ! grep -q "source.*\.devcontainer/\.env" ~/.bashrc 2>/dev/null; then
        echo "" >> ~/.bashrc
        echo "# Source GitHub Actions environment (added by setup-env.sh)" >> ~/.bashrc
        echo "[ -f ${ENV_FILE} ] && set -a && source ${ENV_FILE} && set +a" >> ~/.bashrc
        echo -e "${GREEN}✓${NC} Added source command to ~/.bashrc (tokens stored in .env file)"
    else
        echo -e "${BLUE}ℹ${NC} Source command already in ~/.bashrc"
    fi
fi

echo
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✓ Environment setup complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo
echo "Next steps:"
echo "1. Run 'source $ENV_FILE' to load variables in current session"
echo "2. Run '.devcontainer/verify-env.sh' to verify setup"
echo "3. Rebuild container to apply environment variables via --env-file"
echo
echo -e "${YELLOW}Security Notes:${NC}"
echo "- Tokens are stored in $ENV_FILE (not in ~/.bashrc)"
echo "- File permissions set to 600 (owner read/write only)"
echo "- Remember to rotate tokens periodically"
echo "- Never commit .env file to version control"