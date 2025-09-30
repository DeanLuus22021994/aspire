#!/bin/bash
# quick-start.sh - Quick start guide for new developers
# Single Responsibility: Provide guided setup for new developers

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$SCRIPT_DIR/lib"

# Source required modules
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/file_ops.sh"

# Quick start guide
main() {
    print_header "Aspire DevContainer Quick Start"
    
    echo "Welcome to the .NET Aspire development environment!"
    echo
    echo "This devcontainer includes:"
    echo "• .NET SDK (8.0, 9.0, 10.0 RC)"
    echo "• Azure CLI and Azure Developer CLI (azd)"
    echo "• Docker-in-Docker support"
    echo "• GitHub CLI and Kubernetes tools"
    echo "• Node.js and Python for additional tooling"
    echo
    
    print_subheader "Next Steps"
    echo "1. 📝 Set up environment variables for GitHub Actions integration:"
    echo "   → Run: .devcontainer/scripts/setup-env.sh"
    echo
    echo "2. ✅ Verify your setup:"
    echo "   → Run: .devcontainer/scripts/verify-env.sh"
    echo
    echo "3. 🔧 Set up local .NET SDK:"
    echo "   → Run: ./restore.sh"
    echo
    echo "4. 🏗️ Build the project:"
    echo "   → Run: ./build.sh"
    echo
    echo "5. 🧪 Run tests:"
    echo "   → Run: dotnet test tests/ProjectName.Tests/ProjectName.Tests.csproj -- --filter-not-trait \"quarantined=true\" --filter-not-trait \"outerloop=true\""
    echo
    echo "6. 📋 Use VS Code tasks (Ctrl+Shift+P → 'Tasks: Run Task'):"
    echo "   • Setup Environment Variables"
    echo "   • Verify Environment Variables"
    echo "   • Aspire: Restore & Build"
    echo
    
    print_subheader "Helpful Commands"
    echo "🔍 Check environment: .devcontainer/scripts/verify-env.sh"
    echo "⚙️  Setup environment: .devcontainer/scripts/setup-env.sh --help"
    echo "📚 Read documentation: cat .devcontainer/scripts/README.md"
    echo "🏃 Quick verification: source .devcontainer/.env && .devcontainer/scripts/verify-env.sh"
    echo
    
    if ! file_exists ".devcontainer/.env"; then
        print_warning "Environment not set up yet!"
        echo "Run '.devcontainer/scripts/setup-env.sh' to get started."
        echo
    else
        print_success "Environment file found!"
        echo "Run '.devcontainer/scripts/verify-env.sh' to check your setup."
        echo
    fi
    
    print_info "💡 Tip: This devcontainer uses a modular script architecture for better maintainability."
    print_info "📖 See .devcontainer/scripts/README.md for architecture details."
}

# Execute main function
main "$@"
