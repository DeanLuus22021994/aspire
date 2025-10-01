# .NET Aspire DevContainer

Optimized development container with automated setup, persistent caching, and resource management.

---

## 🚀 Quick Start

### New Users
```bash
git clone https://github.com/DeanLuus22021994/aspire.git
cd aspire
code .
```

**In VS Code:** `F1` → **Dev Containers: Reopen in Container**

⏳ First build: ~10 minutes | Rebuilds: ~75 seconds

---

## 📁 Structure

```text
.devcontainer/
├── Dockerfile                    # Multi-stage build with pre-installed SDK
├── devcontainer.json             # Container configuration
├── .env.example                  # Environment variable template
├── .dockerignore                 # Build context optimization
└── scripts/
    ├── container/                # DevContainer management
    │   ├── build.sh             # Build with logging
    │   ├── inspect.sh           # Inspect running container
    │   ├── logs.sh              # View saved logs
    │   ├── rebuild.sh           # Clean rebuild
    │   └── validate.sh          # Pre-build validation
    ├── environment/              # Environment setup
    │   ├── setup.sh             # Interactive/non-interactive setup
    │   └── verify.sh            # Credential verification
    ├── lifecycle/                # Container lifecycle hooks
    │   ├── init-cache.sh        # Initialize volume caching
    │   ├── init-env.sh          # Load environment variables
    │   └── post-create.sh       # Post-creation validation
    ├── lib/                      # Shared utilities
    │   ├── colors.sh            # Color formatting
    │   ├── docker_api.sh        # Docker API utilities
    │   ├── env_file.sh          # Environment file operations
    │   ├── file_ops.sh          # File operations
    │   ├── github_api.sh        # GitHub API utilities
    │   └── validation.sh        # Input validation
    ├── quick-start.sh            # Quick start guide
    ├── make-executable.sh        # Make scripts executable
    └── test-file-access.sh       # File permission diagnostics
```

---

## 🛠️ Commands

### Container Management

| Script | Command | Description |
|--------|---------|-------------|
| **Build** | `bash scripts/container/build.sh` | Build container with full logging to `/tmp/devcontainer-logs/` |
| **Rebuild** | `bash scripts/container/rebuild.sh` | Clean rebuild without cache (fresh start) |
| **Logs** | `bash scripts/container/logs.sh` | Display saved build/startup logs |
| **Validate** | `bash scripts/container/validate.sh` | Validate configuration before building |
| **Inspect** | `bash scripts/container/inspect.sh` | Inspect running container details |

### Environment Setup

| Script | Command | Description |
|--------|---------|-------------|
| **Setup** | `bash scripts/environment/setup.sh` | Interactive environment variable setup |
| **Verify** | `bash scripts/environment/verify.sh` | Verify credentials (non-destructive) |
| **Quick Start** | `bash scripts/quick-start.sh` | Display quick start guide |

### Lifecycle (Automatic)

| Script | Trigger | Description |
|--------|---------|-------------|
| **init-cache.sh** | `onCreateCommand` | Initialize persistent volume caching |
| **init-env.sh** | `onCreateCommand` | Load environment variables from `.env` |
| **post-create.sh** | `postCreateCommand` | Validate environment after creation |

### Utilities

| Script | Command | Description |
|--------|---------|-------------|
| **Make Executable** | `bash scripts/make-executable.sh` | Make all scripts executable |
| **Test Access** | `bash scripts/test-file-access.sh` | Test file permissions and access |

---

## 🎯 VS Code Tasks

**Access:** `Ctrl+Shift+P` → **Tasks: Run Task**

- **Aspire: Restore & Build** - Full project build
- **Aspire: Full Restore** - Restore local SDK
- **DevContainer: Build and Run** - Build container with logging
- **DevContainer: Rebuild** - Clean rebuild (no cache)
- **DevContainer: Show Logs** - Display saved logs
- **DevContainer: Validate** - Pre-build configuration check
- **DevContainer: Inspect** - Container details and status

---

## 📦 Volume Caching

Persistent Docker volumes for optimal performance:

| Volume | Purpose | Location |
|--------|---------|----------|
| `aspire-nuget-cache` | NuGet packages | `/workspace-cache/nuget` |
| `aspire-build-cache` | Build artifacts | `/workspace-cache/artifacts` |
| `aspire-dotnet-cache` | SDK installations | `/workspace-cache/.dotnet` |

**View cache:**
```bash
docker volume ls | grep aspire
docker volume inspect aspire-nuget-cache
```

**Clear cache:**
```bash
docker volume rm aspire-nuget-cache aspire-build-cache aspire-dotnet-cache
```

---

## ⚙️ Resource Limits

| Resource | Limit | Typical Usage |
|----------|-------|---------------|
| Memory | 8 GB | 2-7 GB |
| CPU | 4 cores | 0.5-380% |
| Disk | 32 GB | 12-18 GB |

---

## 🔧 Configuration

### Environment Variables

Create `.devcontainer/.env` from template:
```bash
cp .devcontainer/.env.example .devcontainer/.env
# Edit with your credentials
```

Required variables:
- `GH_PAT` - GitHub Personal Access Token
- `GITHUB_OWNER` - GitHub username/organization
- `DOCKER_ACCESS_TOKEN` - Docker Hub access token
- `DOCKER_USERNAME` - Docker Hub username

### Adjust Resources

Edit `.devcontainer/devcontainer.json`:
```json
"runArgs": [
    "--memory=16g",      // Increase memory
    "--cpus=8"           // More CPU cores
]
```

---

## 🐛 Troubleshooting

### High Memory Usage
```bash
docker stats  # Should be under 8GB limit
```

### Slow Rebuilds
```bash
# Check volume driver
docker info | grep "Storage Driver"

# Check volume location
docker volume inspect aspire-nuget-cache | jq '.[0].Mountpoint'
```

### SDK Version Mismatch
```bash
# Check installed SDK
dotnet --version
cat global.json | grep version

# Re-run restore if needed
./restore.sh
```

### Container Won't Start
```bash
# View logs
bash .devcontainer/scripts/container/logs.sh

# Validate configuration
bash .devcontainer/scripts/container/validate.sh

# Clean rebuild
bash .devcontainer/scripts/container/rebuild.sh
```

---

## 📊 Performance

| Metric | First Build | Rebuild (Cached) |
|--------|-------------|------------------|
| Docker Build | 6-8 min | 30-60 sec |
| Feature Install | 2-3 min | 15 sec |
| SDK Restore | 40-60 sec | 5 sec |
| **Total** | **~10 min** | **~75 sec** |

---

## 🔄 Automated Setup Flow

```flow
1. Docker Build (SDK pre-installed)
   ↓
2. Feature Installation (Azure CLI, Docker, GitHub CLI, etc.)
   ↓
3. onCreateCommand (Ordered execution)
   ├─ Make scripts executable
   ├─ Initialize cache volumes
   ├─ Run ./restore.sh (local SDK)
   └─ Load environment variables
   ↓
4. postCreateCommand (Validation)
   └─ Verify environment setup
   ↓
5. postStartCommand (Trust certificates)
   └─ Trust dev-certs
   ↓
✅ READY TO DEVELOP
```

---

## 📝 Notes

- **First build** takes ~10 minutes (SDK download + feature installation)
- **Subsequent builds** take ~75 seconds (everything cached)
- **Volumes persist** across container rebuilds
- **All scripts** made executable automatically
- **Zero manual steps** required - fully automated

---

**Version:** 2.0 (Optimized & Reorganized)
**Last Updated:** October 1, 2025
