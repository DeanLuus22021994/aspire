#!/bin/bash
# github_api.sh - GitHub API verification utilities
# Single Responsibility: Handle GitHub API authentication and runner verification

set -euo pipefail

# Source required dependencies
SCRIPT_LIB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_LIB_DIR/colors.sh"
source "$SCRIPT_LIB_DIR/validation.sh"

# GitHub API endpoints
readonly GITHUB_API_BASE="https://api.github.com"
readonly GITHUB_USER_ENDPOINT="$GITHUB_API_BASE/user"

# Check if jq is available for JSON parsing
is_jq_available() {
    command -v jq >/dev/null 2>&1
}

# Parse JSON response (with fallback if jq not available)
parse_json_field() {
    local json="$1"
    local field="$2"
    
    if is_jq_available; then
        echo "$json" | jq -r ".$field // \"\"" 2>/dev/null || echo ""
    else
        # Fallback grep/cut parsing
        echo "$json" | grep -o "\"$field\":[^,}]*" | cut -d':' -f2- | sed 's/^[[:space:]]*\"\|\"[[:space:]]*$//g' | head -1 || echo ""
    fi
}

# Make authenticated GitHub API request
github_api_request() {
    local endpoint="$1"
    local token="$2"
    local method="${3:-GET}"
    
    curl -s -X "$method" \
        -H "Authorization: token $token" \
        -H "Accept: application/vnd.github.v3+json" \
        "$endpoint" 2>/dev/null || echo ""
}

# Get GitHub user information
get_github_user_info() {
    local token="$1"
    github_api_request "$GITHUB_USER_ENDPOINT" "$token"
}

# Get GitHub token scopes
get_github_token_scopes() {
    local token="$1"
    
    local scopes_response
    scopes_response=$(curl -sI -H "Authorization: token $token" "$GITHUB_USER_ENDPOINT" 2>/dev/null | \
        grep -i "x-oauth-scopes:" | cut -d: -f2- | tr -d ' \r' || echo "")
    
    echo "$scopes_response"
}

# Verify GitHub token with detailed feedback
verify_github_token() {
    local token="${1:-${GH_PAT:-}}"
    
    if is_empty "$token"; then
        print_warning "GitHub token not set - skipping verification"
        return 0
    fi
    
    print_subheader "GitHub Token Verification (non-destructive)"
    
    local user_info
    user_info=$(get_github_user_info "$token")
    
    if is_not_empty "$user_info" && echo "$user_info" | grep -q '"login"'; then
        local user_login
        user_login=$(parse_json_field "$user_info" "login")
        
        if is_not_empty "$user_login"; then
            print_success "GitHub token valid for user: $user_login"
            
            # Check if token user matches GITHUB_OWNER
            if is_not_empty "${GITHUB_OWNER:-}"; then
                if [ "$user_login" = "$GITHUB_OWNER" ]; then
                    print_success "Token user matches GITHUB_OWNER"
                else
                    print_warning "Token user ($user_login) differs from GITHUB_OWNER ($GITHUB_OWNER)"
                fi
            fi
            
            # Check token scopes
            local scopes
            scopes=$(get_github_token_scopes "$token")
            
            if is_not_empty "$scopes"; then
                print_info "Token Scopes: $scopes"
                
                if [[ "$scopes" == *"repo"* ]]; then
                    print_success "Has 'repo' scope"
                fi
                
                if [[ "$scopes" == *"workflow"* ]]; then
                    print_success "Has 'workflow' scope"
                fi
            fi
            
            return 0
        fi
    fi
    
    # Handle API errors
    local error_msg
    error_msg=$(parse_json_field "$user_info" "message")
    
    if is_not_empty "$error_msg"; then
        print_error "GitHub API error: $error_msg"
    else
        print_error "GitHub token verification failed"
    fi
    
    return 1
}

# Get runners for organization
get_org_runners() {
    local token="$1"
    local org="$2"
    
    local org_url="$GITHUB_API_BASE/orgs/$org/actions/runners"
    github_api_request "$org_url" "$token"
}

# Get runners for repository
get_repo_runners() {
    local token="$1"
    local owner="$2"
    local repo="$3"
    
    local repo_url="$GITHUB_API_BASE/repos/$owner/$repo/actions/runners"
    github_api_request "$repo_url" "$token"
}

# Parse runner count from API response
get_runner_count() {
    local api_response="$1"
    
    if is_jq_available; then
        echo "$api_response" | jq -r '.total_count // 0' 2>/dev/null || echo "0"
    else
        echo "$api_response" | grep -o '"total_count"[[:space:]]*:[[:space:]]*[0-9]*' | \
            head -1 | grep -o '[0-9]*' || echo "0"
    fi
}

# List runners from API response
list_runners() {
    local api_response="$1"
    
    if is_jq_available; then
        echo "$api_response" | jq -r '.runners[]? | "- \(.name) (status: \(.status))"' 2>/dev/null || true
    else
        # Simplified fallback - just indicate runners exist
        local count
        count=$(get_runner_count "$api_response")
        if [ "$count" -gt 0 ]; then
            print_info "$count runner(s) registered (use jq for detailed listing)"
        fi
    fi
}

# Verify self-hosted runner registration
verify_runner_registration() {
    local token="${1:-${GH_PAT:-}}"
    local owner="${2:-${GITHUB_OWNER:-}}"
    
    if is_empty "$token" || is_empty "$owner"; then
        print_warning "Missing GH_PAT or GITHUB_OWNER - cannot verify runner registration"
        return 0
    fi
    
    print_subheader "Self-hosted Runner Registration Check"
    
    # Try organization-level runners first
    local org_response
    org_response=$(get_org_runners "$token" "$owner")
    
    if is_not_empty "$org_response" && ! echo "$org_response" | grep -q '"message"'; then
        local org_count
        org_count=$(get_runner_count "$org_response")
        
        if [ "$org_count" -gt 0 ]; then
            print_success "Found $org_count self-hosted runner(s) at org scope for $owner"
            list_runners "$org_response"
            return 0
        fi
    fi
    
    # Try repository-level runners
    local repo_response
    repo_response=$(get_repo_runners "$token" "$owner" "aspire")
    
    if is_not_empty "$repo_response" && ! echo "$repo_response" | grep -q '"message"'; then
        local repo_count
        repo_count=$(get_runner_count "$repo_response")
        
        if [ "$repo_count" -gt 0 ]; then
            print_success "Found $repo_count self-hosted runner(s) for repository $owner/aspire"
            list_runners "$repo_response"
            return 0
        fi
    fi
    
    # No runners found
    print_warning "No self-hosted runners found for org or repository. Register a runner to proceed."
    return 1
}

# Validate runner token format
validate_runner_token() {
    local token="${1:-${GITHUB_RUNNER_TOKEN:-}}"
    
    if is_empty "$token"; then
        return 0
    fi
    
    print_subheader "GitHub Runner Token Format Check"
    
    if validate_runner_token_format "$token"; then
        print_success "Runner token format appears valid"
        print_info "Runner tokens expire after 1 hour"
    else
        print_warning "Runner token format may be incorrect"
        return 1
    fi
    
    return 0
}