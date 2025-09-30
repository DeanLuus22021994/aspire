# Use the official Microsoft devcontainer base image for .NET
FROM mcr.microsoft.com/devcontainers/dotnet:dev-10.0-preview-noble

# Accept build argument for devcontainer-cli
ARG devcontainercli=false

# Install additional tools if needed
RUN if [ "$devcontainercli" = "true" ]; then \
        echo "DevContainer CLI build detected"; \
    fi

# Set the default working directory
WORKDIR /workspaces/aspire