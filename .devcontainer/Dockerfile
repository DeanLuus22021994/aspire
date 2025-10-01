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

# Stage 3: Final devcontainer image
FROM base AS final

# Copy pre-installed SDK from previous stage
ARG DOTNET_INSTALL_DIR=/opt/dotnet-sdk
COPY --from=sdk-installer ${DOTNET_INSTALL_DIR} ${DOTNET_INSTALL_DIR}

# Set environment variables for SDK
ENV DOTNET_ROOT=${DOTNET_INSTALL_DIR}
ENV PATH="${DOTNET_INSTALL_DIR}:${PATH}"

# Create workspace directory structure
RUN mkdir -p /workspaces/aspire && \
    mkdir -p /workspace-cache/.dotnet && \
    mkdir -p /workspace-cache/artifacts && \
    mkdir -p /workspace-cache/nuget && \
    chown -R vscode:vscode /workspace-cache

# Set working directory
WORKDIR /workspaces/aspire

# Configure NuGet to use volume cache
ENV NUGET_PACKAGES=/workspace-cache/nuget
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

# Pre-warm NuGet cache with common packages (optional, saves time)
# This reduces first-build time significantly
RUN dotnet new list > /dev/null 2>&1 || true

# Labels for identification
LABEL dev.containers.sdk.version="${DOTNET_VERSION}"
LABEL dev.containers.cache.enabled="true"
