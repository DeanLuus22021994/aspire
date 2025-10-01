# Multi-stage build for optimized devcontainer
# Stage 1: Base with system dependencies
FROM mcr.microsoft.com/devcontainers/dotnet:dev-10.0-preview-noble AS base

# Install system dependencies and tools in single layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        apt-transport-https \
        build-essential \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        libssl-dev \
        unzip \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Stage 2: SDK installation (can be cached)
FROM base AS sdk-installer

# Accept build argument for .NET SDK version (must match global.json)
ARG DOTNET_VERSION=10.0.100-rc.1.25420.111
ARG DOTNET_INSTALL_DIR=/opt/dotnet-sdk

# Download and install .NET SDK to persistent location
RUN mkdir -p ${DOTNET_INSTALL_DIR} && \
    curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- \
        --version ${DOTNET_VERSION} \
        --install-dir ${DOTNET_INSTALL_DIR} \
        --no-path && \
    chmod -R 755 ${DOTNET_INSTALL_DIR}

# Stage 3: Restore dependencies (build-time caching)
FROM base AS restore-builder

# Copy pre-installed SDK from previous stage
ARG DOTNET_INSTALL_DIR=/opt/dotnet-sdk
COPY --from=sdk-installer ${DOTNET_INSTALL_DIR} ${DOTNET_INSTALL_DIR}

# Set environment variables for SDK
ENV DOTNET_ROOT=${DOTNET_INSTALL_DIR}
ENV PATH="${DOTNET_INSTALL_DIR}:${PATH}"
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

# Create build workspace and cache directories
RUN mkdir -p /build-workspace/aspire && \
    mkdir -p /build-cache/nuget && \
    mkdir -p /build-cache/.dotnet

# Set NuGet cache location for build
ENV NUGET_PACKAGES=/build-cache/nuget

# Copy only the files needed for restore (for better layer caching)
WORKDIR /build-workspace/aspire
COPY global.json NuGet.config ./
COPY Directory.Build.props Directory.Build.targets Directory.Packages.props ./
COPY eng/ ./eng/

# Make eng scripts executable (avoids WSL2 chmod issue)
RUN find ./eng -type f -name "*.sh" -exec chmod +x {} \; && \
    chmod +x ./eng/build.sh

# Run restore using the Aspire build script
# This populates the NuGet cache during Docker build (not in WSL2 mount)
RUN ./eng/build.sh --restore || true

# Stage 4: Final devcontainer image
FROM base AS final

# Copy pre-installed SDK from previous stage
ARG DOTNET_INSTALL_DIR=/opt/dotnet-sdk
COPY --from=sdk-installer ${DOTNET_INSTALL_DIR} ${DOTNET_INSTALL_DIR}

# Copy pre-restored NuGet cache from restore-builder stage
COPY --from=restore-builder /build-cache/nuget /workspace-cache/nuget
COPY --from=restore-builder /build-cache/.dotnet /workspace-cache/.dotnet

# Set environment variables for SDK
ENV DOTNET_ROOT=${DOTNET_INSTALL_DIR}
ENV PATH="${DOTNET_INSTALL_DIR}:${PATH}"

# Create workspace directory structure
RUN mkdir -p /workspaces/aspire && \
    mkdir -p /workspace-cache/artifacts && \
    chown -R vscode:vscode /workspace-cache

# Set working directory
WORKDIR /workspaces/aspire

# Configure NuGet to use cached packages
ENV NUGET_PACKAGES=/workspace-cache/nuget
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

# Labels for identification
LABEL dev.containers.sdk.version="${DOTNET_VERSION}"
LABEL dev.containers.cache.enabled="true"
LABEL dev.containers.restore.prebuilt="true"
