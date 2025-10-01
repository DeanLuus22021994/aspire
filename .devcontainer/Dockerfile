# Use the official Microsoft devcontainer base image for .NET
FROM mcr.microsoft.com/devcontainers/dotnet:dev-10.0-preview-noble

# Accept build argument for .NET SDK version (should match global.json)
ARG DOTNET_VERSION=10.0.100-rc.1.25420.111

# Install prerequisites
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        jq \
        unzip && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspaces/aspire

# Note: The base image already includes .NET SDK
# The local SDK will be installed by ./restore.sh during onCreateCommand
# This ensures alignment with global.json requirements