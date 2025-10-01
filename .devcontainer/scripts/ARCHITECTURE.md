# DevContainer Scripts Architecture

## Directory Structure

```
.devcontainer/scripts/
├── container/          # Container management operations
├── environment/        # Environment setup and configuration
├── lib/               # Shared libraries and utilities
├── lifecycle/         # Container lifecycle hooks
└── python/            # Python-specific operations
```

## Standardized Naming Conventions

### Script Names
- **Action scripts**: `<action>-<resource>.sh` (e.g., `validate-permissions.sh`)
- **Initialization scripts**: `init-<resource>.sh` (e.g., `init-cache.sh`)
- **Utility scripts**: `<utility-name>.sh` (e.g., `colors.sh`)

### Function Names
- **Public functions**: `action_resource()` (e.g., `ensure_permissions()`)
- **Private functions**: `_action_resource()` (e.g., `_wait_for_write_access()`)
- **Validation functions**: `validate_resource()` (e.g., `validate_permissions()`)

### Variable Names
- **Constants**: `UPPER_SNAKE_CASE` (e.g., `MAX_WAIT_SECONDS`)
- **Global variables**: `CAPITALIZED_SNAKE_CASE` (e.g., `Workspace_Path`)
- **Local variables**: `lower_snake_case` (e.g., `wait_count`)

## Module Responsibilities

### `/lib` - Shared Libraries
- **colors.sh**: Color constants and formatting functions
- **validation.sh**: Common validation utilities
- **file_ops.sh**: File system operations
- **docker_api.sh**: Docker API interactions
- **github_api.sh**: GitHub API interactions
- **env_file.sh**: Environment file management

### `/lifecycle` - Container Lifecycle Hooks
- **init-permissions.sh**: Permission initialization (NEW)
- **init-cache.sh**: Workspace cache initialization
- **init-python-cache.sh**: Python cache detection and reporting
- **post-create-validation.sh**: Post-creation validation

### `/python` - Python Management (NEW)
- **install-python.sh**: Python installation with caching
- **install-tools.sh**: Python tools installation with caching
- **validate-cache.sh**: Python cache validation

### `/container` - Container Operations
- **build.sh**: Build container
- **rebuild.sh**: Rebuild container
- **cleanup.sh**: Cleanup resources
- **validate.sh**: Pre-build validation
- **inspect.sh**: Inspect running container
- **logs.sh**: View container logs
- **config.sh**: Display configuration
- **exec.sh**: Execute commands in container

### `/environment` - Environment Configuration
- **setup.sh**: Environment setup
- **verify.sh**: Environment verification

## Execution Flow

### Container Creation (onCreateCommand)
```
1. init-permissions.sh     → Ensure workspace permissions
2. init-python-cache.sh    → Detect Python cache state
3. init-cache.sh           → Initialize workspace caches
4. restore.sh              → Run .NET restore
5. init-env.sh             → Initialize environment variables
```

### Post Creation (postCreateCommand)
```
1. post-create-validation.sh → Validate container setup
```

## Cross-Cutting Concerns

### Error Handling
- All scripts return proper exit codes
- Use `set -euo pipefail` for strict error handling
- Provide meaningful error messages with context

### Logging
- Use consistent log format: `[LEVEL] Message`
- Leverage colors.sh for visual clarity
- Support quiet mode via `QUIET=1` environment variable

### Permissions
- Always use `2>/dev/null || true` for non-critical chown operations
- Validate write access before critical operations
- Provide fallback mechanisms

### Caching
- Cache detection before operation
- Atomic cache updates
- Cache invalidation strategies

## Migration Plan

### Phase 1: Reorganization
1. Create `/python` directory
2. Move Python scripts to proper locations
3. Create `init-permissions.sh`

### Phase 2: Refactoring
1. Extract common functions to `/lib`
2. Standardize naming conventions
3. Add comprehensive error handling

### Phase 3: Integration
1. Update devcontainer.json with new script paths
2. Test all lifecycle hooks
3. Update documentation

### Phase 4: Validation
1. Run validation scripts
2. Test permission handling
3. Verify Python caching
