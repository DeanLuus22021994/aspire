#!/bin/bash
# test-file-access.sh - Test file access and permissions

echo "=== Testing File Access ==="
echo "Current directory: $(pwd)"
echo "Current user: $(whoami)"
echo ""

echo "--- Testing file existence ---"
files_to_check=(
    ".devcontainer/devcontainer.json"
    ".devcontainer/Dockerfile"
    ".vscode/tasks.json"
    "global.json"
    "restore.sh"
    "build.sh"
)

for file in "${files_to_check[@]}"; do
    if [ -f "$file" ]; then
        perms=$(stat -c "%a %U:%G" "$file" 2>/dev/null || stat -f "%Lp %Su:%Sg" "$file" 2>/dev/null)
        size=$(stat -c "%s" "$file" 2>/dev/null || stat -f "%z" "$file" 2>/dev/null)
        echo "✓ $file (${perms}, ${size} bytes)"
        
        # Test if readable
        if [ -r "$file" ]; then
            echo "  └─ readable ✓"
        else
            echo "  └─ NOT readable ✗"
        fi
    else
        echo "✗ $file NOT FOUND"
    fi
done

echo ""
echo "--- Testing JSON parsing ---"
if command -v jq &> /dev/null; then
    echo "jq is installed: $(which jq)"
    echo "jq version: $(jq --version)"
    
    # Test reading devcontainer.json
    echo ""
    echo "Testing .devcontainer/devcontainer.json:"
    if [ -f ".devcontainer/devcontainer.json" ]; then
        if jq -e '.name' .devcontainer/devcontainer.json >/dev/null 2>&1; then
            name=$(jq -r '.name' .devcontainer/devcontainer.json)
            echo "✓ Successfully parsed - Name: $name"
        else
            echo "✗ Failed to parse JSON"
            echo "Error output:"
            jq -e '.name' .devcontainer/devcontainer.json 2>&1
        fi
    fi
else
    echo "✗ jq is not installed"
    echo "Install with: apt-get install jq"
fi

echo ""
echo "=== Test Complete ==="