#!/bin/bash
# filepath: .devcontainer/verify-env.sh

set -euo pipefail

echo "========================================="
echo "  Environment Variables Verification"
echo "========================================="
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Required and optional command checks
REQUIRED_COMMANDS=(curl stat)
OPTIONAL_COMMANDS=(docker jq)

MISSING_REQUIRED=()
AVAILABLE_DOCKER=false
AVAILABLE_JQ=false

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_REQUIRED+=("$cmd")
    fi
done

for cmd in "${OPTIONAL_COMMANDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        if [ "$cmd" = "docker" ]; then AVAILABLE_DOCKER=true; fi
        if [ "$cmd" = "jq" ]; then AVAILABLE_JQ=true; fi
    fi
done

if [ "${#MISSING_REQUIRED[@]}" -gt 0 ]; then
    echo -e "${RED}Missing required tools:${NC} ${MISSING_REQUIRED[*]}"
    echo "Install the missing tools and re-run verification (e.g. apt/apt-get, package manager or include in devcontainer features)."
    exit 2
fi

if [ "$AVAILABLE_DOCKER" = false ]; then
    echo -e "${YELLOW}Warning:${NC} 'docker' not found. Docker checks will be skipped."
fi

if [ "$AVAILABLE_JQ" = false ]; then
    echo -e "${YELLOW}Note:${NC} 'jq' not found. JSON parsing will use lightweight grep/cut fallback."
fi

# Use temporary Docker config to avoid side effects
TEMP_DOCKER_CONFIG=""

# Cleanup function
cleanup() {
    if [ -n "$TEMP_DOCKER_CONFIG" ] && [ -d "$TEMP_DOCKER_CONFIG" ]; then
        rm -rf "$TEMP_DOCKER_CONFIG"
    fi
}

trap cleanup EXIT

# Function to check if a variable is set and not empty
check_env_var() {
    local var_name=$1
    local is_secret=${2:-false}
    local var_value="${!var_name:-}"
    
    if [ -z "$var_value" ]; then
        echo -e "${RED}✗${NC} $var_name: ${RED}NOT SET${NC}"
        return 1
    else
        if [ "$is_secret" = true ]; then
            echo -e "${GREEN}✓${NC} $var_name: ${GREEN}SET${NC} (${BLUE}length: ${#var_value}${NC})"
        else
            echo -e "${GREEN}✓${NC} $var_name: ${GREEN}$var_value${NC}"
        fi
        return 0
    fi
}

# Non-destructive GitHub token verification
verify_github_token_safe() {
    if [ -z "${GH_PAT:-}" ]; then
        echo -e "${YELLOW}⚠${NC} GitHub token not set - skipping verification"
        return 0
    fi
    
    echo
    echo -e "${BLUE}GitHub Token Verification (non-destructive):${NC}"
    
    local user_info
    user_info=$(curl -s -H "Authorization: token $GH_PAT" https://api.github.com/user 2>/dev/null || true)
    
    if [ -n "$user_info" ] && echo "$user_info" | grep -q '"login"'; then
        local user_login
        if [ "$AVAILABLE_JQ" = true ]; then
            user_login=$(echo "$user_info" | jq -r .login)
        else
            user_login=$(echo "$user_info" | grep -o '"login":"[^"]*"' | cut -d'"' -f4)
        fi
        echo -e "${GREEN}✓${NC} GitHub token valid for user: ${GREEN}$user_login${NC}"
        
        if [ -n "${GITHUB_OWNER:-}" ]; then
            if [ "$user_login" = "$GITHUB_OWNER" ]; then
                echo -e "${GREEN}✓${NC} Token user matches GITHUB_OWNER"
            else
                echo -e "${YELLOW}⚠${NC} Token user ($user_login) differs from GITHUB_OWNER ($GITHUB_OWNER)"
            fi
        fi
        
        # Check scopes using headers
        local scopes_response
        scopes_response=$(curl -sI -H "Authorization: token $GH_PAT" https://api.github.com/user 2>/dev/null | grep -i "x-oauth-scopes:" | cut -d: -f2- | tr -d ' \r' || true)
        if [ -n "$scopes_response" ]; then
            echo -e "${BLUE}Token Scopes:${NC} $scopes_response"
            if [[ "$scopes_response" == *"repo"* ]]; then echo -e "${GREEN}✓${NC} Has 'repo' scope"; fi
            if [[ "$scopes_response" == *"workflow"* ]]; then echo -e "${GREEN}✓${NC} Has 'workflow' scope"; fi
        fi
    else
        local error_msg
        error_msg=$(echo "$user_info" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || true)
        if [ -n "$error_msg" ]; then
            echo -e "${RED}✗${NC} GitHub API error: $error_msg"
        else
            echo -e "${RED}✗${NC} GitHub token verification failed"
        fi
    fi
}

# Non-destructive Docker credentials verification
verify_docker_credentials_safe() {
    if [ -z "${DOCKER_USERNAME:-}" ] || [ -z "${DOCKER_ACCESS_TOKEN:-}" ]; then
        echo -e "${YELLOW}⚠${NC} Docker credentials not set - skipping verification"
        return 0
    fi
    
    if [ "$AVAILABLE_DOCKER" = false ]; then
        echo -e "${YELLOW}⚠${NC} Docker CLI not available - skipping docker login test"
        # Still try Docker Hub API test via curl
        local auth_string
        auth_string=$(echo -n "$DOCKER_USERNAME:$DOCKER_ACCESS_TOKEN" | base64)
        local api_response
        api_response=$(curl -s -H "Authorization: Basic $auth_string" https://hub.docker.com/v2/user/ 2>/dev/null || true)
        if [ -n "$api_response" ] && echo "$api_response" | grep -q '"username"'; then
            echo -e "${GREEN}✓${NC} Docker Hub API authentication appears successful (via curl)"
        else
            echo -e "${YELLOW}⚠${NC} Could not fully verify Docker credentials without docker CLI"
        fi
        return 0
    fi
    
    echo
    echo -e "${BLUE}Docker Credentials Verification (non-destructive):${NC}"
    
    TEMP_DOCKER_CONFIG=$(mktemp -d)
    export DOCKER_CONFIG="$TEMP_DOCKER_CONFIG"
    
    # API check first
    local auth_string
    auth_string=$(echo -n "$DOCKER_USERNAME:$DOCKER_ACCESS_TOKEN" | base64)
    local api_response
    api_response=$(curl -s -H "Authorization: Basic $auth_string" https://hub.docker.com/v2/user/ 2>/dev/null || true)
    
    if [ -n "$api_response" ] && echo "$api_response" | grep -q '"username"'; then
        echo -e "${GREEN}✓${NC} Docker Hub API authentication successful"
    else
        echo -e "${YELLOW}⚠${NC} Docker Hub API authentication inconclusive"
    fi
    
    # Try docker login in isolated config
    if echo "$DOCKER_ACCESS_TOKEN" | docker --config "$TEMP_DOCKER_CONFIG" login --username "$DOCKER_USERNAME" --password-stdin docker.io &>/dev/null; then
        echo -e "${GREEN}✓${NC} Docker registry login successful (isolated test)"
        docker --config "$TEMP_DOCKER_CONFIG" logout docker.io &>/dev/null || true
    else
        echo -e "${YELLOW}⚠${NC} Docker login test inconclusive or failed (isolated)"
    fi
    
    unset DOCKER_CONFIG
}

# Function to test GitHub Runner Token
verify_runner_token() {
    if [ -z "${GITHUB_RUNNER_TOKEN:-}" ]; then
        return 0
    fi
    
    echo
    echo -e "${BLUE}GitHub Runner Token Format Check:${NC}"
    
    if [[ "$GITHUB_RUNNER_TOKEN" =~ ^[A-Z0-9]{20,}$ ]]; then
        echo -e "${GREEN}✓${NC} Runner token format appears valid"
        echo -e "${BLUE}Note:${NC} Runner tokens expire after 1 hour"
    else
        echo -e "${YELLOW}⚠${NC} Runner token format may be incorrect"
    fi
}

# Check for .env file
check_env_file() {
    echo
    echo -e "${BLUE}Environment File Check:${NC}"
    
    if [ -f .devcontainer/.env ]; then
        echo -e "${GREEN}✓${NC} .devcontainer/.env file exists"
        local perms
        perms=$(stat -c %a .devcontainer/.env 2>/dev/null || stat -f %p .devcontainer/.env 2>/dev/null || echo "unknown")
        if [ "$perms" = "600" ]; then
            echo -e "${GREEN}✓${NC} .env file has secure permissions (600)"
        else
            echo -e "${YELLOW}⚠${NC} .env file permissions are $perms (recommend 600)"
        fi
        
        if [ -f .gitignore ] && grep -q "\.devcontainer/\.env" .gitignore; then
            echo -e "${GREEN}✓${NC} .env file is in .gitignore"
        else
            echo -e "${RED}✗${NC} .env file is NOT in .gitignore - security risk!"
        fi
    else
        echo -e "${BLUE}ℹ${NC} No .devcontainer/.env file found"
        echo "  Run .devcontainer/setup-env.sh to create one"
    fi
}

# Main verification
echo -e "${BLUE}Required Environment Variables:${NC}"

overall_status=0
check_env_var "GH_PAT" true || overall_status=$((overall_status + 1))
check_env_var "GITHUB_OWNER" false || overall_status=$((overall_status + 1))
check_env_var "GITHUB_RUNNER_TOKEN" true || overall_status=$((overall_status + 1))
check_env_var "DOCKER_ACCESS_TOKEN" true || overall_status=$((overall_status + 1))
check_env_var "DOCKER_USERNAME" false || overall_status=$((overall_status + 1))

echo
echo -e "${BLUE}Additional Aspire Environment Variables:${NC}"
check_env_var "ASPIRE_ALLOW_UNSECURED_TRANSPORT" false || true
check_env_var "DOTNET_DASHBOARD_OTLP_ENDPOINT_URL" false || true
check_env_var "DOTNET_DASHBOARD_UNSECURED_ALLOW_ANONYMOUS" false || true

check_env_file

verify_github_token_safe
verify_docker_credentials_safe
verify_runner_token

echo
echo -e "${BLUE}Development Environment Check:${NC}"
if echo "$PATH" | grep -q "/workspaces/aspire/artifacts/bin/Aspire.Cli"; then
    echo -e "${GREEN}✓${NC} Aspire CLI path is in PATH"
else
    echo -e "${YELLOW}⚠${NC} Aspire CLI path not found in PATH"
fi

if [ -f /workspaces/aspire/.devcontainer/devcontainer.json ]; then
    echo -e "${GREEN}✓${NC} Running in Aspire devcontainer"
else
    echo -e "${YELLOW}⚠${NC} Not detected as running in Aspire devcontainer"
fi

echo
echo "========================================="
if [ $overall_status -eq 0 ]; then
    echo -e "${GREEN}✓ All required environment variables are set!${NC}"
    echo -e "${GREEN}✓ Non-destructive verification completed${NC}"
else
    echo -e "${RED}✗ $overall_status required environment variable(s) missing${NC}"
    echo -e "${YELLOW}⚠ Run: .devcontainer/setup-env.sh${NC}"
fi
echo "========================================="

exit $overall_status