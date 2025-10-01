#!/bin/bash
# colors.sh - Color constants and formatting utilities
# Single Responsibility: Provide consistent color formatting across scripts

set -euo pipefail

# Color constants (check if already defined to avoid readonly conflicts)
if [ -z "${RED:-}" ]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m' # No Color
fi

# Color utility functions
color_print() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

print_success() {
    color_print "$GREEN" "✓ $1"
}

print_error() {
    color_print "$RED" "✗ $1"
}

print_warning() {
    color_print "$YELLOW" "⚠ $1"
}

print_info() {
    color_print "$BLUE" "ℹ $1"
}

print_header() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo
}

print_subheader() {
    echo
    echo -e "${BLUE}$1:${NC}"
}
