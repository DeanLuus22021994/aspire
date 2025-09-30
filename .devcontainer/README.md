# DevContainer Environment Setup for GitHub Actions Runner

This directory contains scripts and configuration for setting up GitHub Actions runner environment variables securely in the devcontainer.

## Quick Start

1. **Run the setup script**:
   ```bash
   .devcontainer/setup-env.sh
   ```

2. **Verify the setup**:
   ```bash
   .devcontainer/verify-env.sh
   ```

3. **Rebuild the container** to apply the environment variables.

## Security Best Practices

- **Never commit `.env` files** to version control
- Environment variables are stored in `.devcontainer/.env` with 600 permissions
- The `.env` file is automatically added to `.gitignore`
- Tokens are NOT stored directly in `~/.bashrc`
- Use the non-destructive verification script to test credentials

## Files

- `setup-env.sh` - Interactive/non-interactive setup script
- `verify-env.sh` - Non-destructive verification of credentials
- `init-env.sh` - Automatic initialization on container creation
- `.env.example` - Template for environment variables
- `.env` - Actual environment file (git-ignored)

## Non-Interactive Setup

For automation, you can use non-interactive mode:

```bash
# Create your .env file first
cp .devcontainer/.env.example .devcontainer/.env
# Edit .env with your values
vim .devcontainer/.env

# Run setup non-interactively
.devcontainer/setup-env.sh --from-file .devcontainer/.env
```

## VS Code Tasks

Use the Command Palette (`Ctrl+Shift+P`) and run "Tasks: Run Task" to access:

- **Setup Environment Variables** - Interactive setup
- **Verify Environment Variables** - Non-destructive verification
- **Clean Environment Variables** - Remove variables and restore backups

## Environment Variables Required

- `GH_PAT` - GitHub Personal Access Token (needs `repo` and `workflow` scopes)
- `GITHUB_OWNER` - GitHub username or organization
- `GITHUB_RUNNER_TOKEN` - Runner registration token (optional, expires after 1 hour)
- `DOCKER_ACCESS_TOKEN` - Docker Hub access token
- `DOCKER_USERNAME` - Docker Hub username

## Troubleshooting

If environment variables are not available after setup:

1. Ensure `.devcontainer/.env` exists and has proper permissions (600)
2. Rebuild the container to apply `--env-file` configuration
3. Run `source .devcontainer/.env` in your current shell session