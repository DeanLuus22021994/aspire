#!/bin/bash
# file_ops.sh - File operation utilities
# Single Responsibility: Handle file operations, permissions, and validation

set -euo pipefail

# Source required dependencies
SCRIPT_LIB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_LIB_DIR/colors.sh"

# File validation functions
file_exists() {
    [ -f "$1" ]
}

dir_exists() {
    [ -d "$1" ]
}

file_readable() {
    [ -r "$1" ]
}

file_writable() {
    [ -w "$1" ]
}

# Permission functions
set_secure_permissions() {
    local file="$1"
    if chmod 600 "$file" 2>/dev/null; then
        print_success "Set secure permissions (600) on $file"
        return 0
    else
        print_warning "Could not set permissions to 600 on $file"
        return 1
    fi
}

get_file_permissions() {
    local file="$1"
    stat -c %a "$file" 2>/dev/null || stat -f %p "$file" 2>/dev/null || echo "unknown"
}

# Ownership functions
set_container_ownership() {
    local file="$1"
    local container_uid container_gid
    
    container_uid=$(id -u)
    container_gid=$(id -g)
    
    if chown "$container_uid:$container_gid" "$file" 2>/dev/null; then
        print_success "Changed ownership of $file to UID:GID $container_uid:$container_gid"
        return 0
    else
        print_warning "Could not change ownership of $file (likely bind-mounted from host)"
        return 1
    fi
}

# Backup functions
create_backup() {
    local file="$1"
    local backup_suffix="${2:-.backup.$(date +%Y%m%d_%H%M%S)}"
    local backup_file="${file}${backup_suffix}"
    
    if file_exists "$file"; then
        cp "$file" "$backup_file"
        print_success "Created backup: $backup_file"
        echo "$backup_file"
    else
        print_warning "Source file $file does not exist, skipping backup"
        return 1
    fi
}

# Directory creation with error handling
ensure_directory() {
    local dir="$1"
    if ! dir_exists "$dir"; then
        if mkdir -p "$dir" 2>/dev/null; then
            print_success "Created directory: $dir"
        else
            print_error "Failed to create directory: $dir"
            return 1
        fi
    fi
}

# Safe file writing
write_file_safely() {
    local file="$1"
    local content="$2"
    local temp_file
    
    temp_file="$(dirname "$file")/.$(basename "$file").tmp"
    
    if echo "$content" > "$temp_file" && mv "$temp_file" "$file"; then
        print_success "Successfully wrote $file"
        return 0
    else
        print_error "Failed to write $file"
        rm -f "$temp_file" 2>/dev/null || true
        return 1
    fi
}