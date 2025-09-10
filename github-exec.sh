#!/bin/bash
set -euo pipefail

# Default values
CACHE_DIR="${HOME}/.cache/github-exec"
VERSION="latest"
FORCE=false

# Detect Ubuntu version from /etc/os-release
detect_ubuntu_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" = "ubuntu" ]; then
            echo "ubuntu$VERSION_ID"
            return 0
        fi
    fi
    echo ""
}

# Usage information
usage() {
    cat << EOF
github-exec - Execute binaries from GitHub releases

Usage: github-exec [OPTIONS] <user/repo> <executable> [args...]
       curl -sSL https://raw.githubusercontent.com/zacuke/github-exec/main/github-exec.sh | bash -s -- [OPTIONS] <user/repo> <executable> [args...]

Options:
  --version VERSION    Use specific version instead of latest
  --force              Force redownload
  --help               Show this help
  --cache-dir DIR      Custom cache directory (default: ~/.cache/github-exec)

Examples:
  github-exec zacuke/run-node index.js
  github-exec --version v1.2.3 zacuke/some-tool --help

EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                VERSION="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help)
                usage
                ;;
            --cache-dir)
                CACHE_DIR="$2"
                shift 2
                ;;
            -*)
                echo "Unknown option: $1" >&2
                usage
                ;;
            *)
                break
                ;;
        esac
    done
if [ $# -lt 1 ]; then
    usage
fi

REPO="$1"
shift
# The executable is actually the first argument to pass to the downloaded binary
ARGS=("$@")
}

# Clean up temporary cache
cleanup() {
    if [[ "$CACHE_DIR" == /tmp/github-exec-* ]]; then
        rm -rf "$CACHE_DIR" 2>/dev/null || true
    fi
}

# Extract download URL from JSON for a specific asset name - SIMPLIFIED
extract_download_url() {
    local json="$1"
    local asset_name="$2"
    
    # Use a simple pattern that matches the download URL format
    echo "$json" | grep -o "\"browser_download_url\": \"[^\"]*$asset_name[^\"]*\"" | \
    head -1 | \
    cut -d'"' -f4
}

# Clean asset names - remove empty lines and trim whitespace
clean_asset_list() {
    local assets="$1"
    echo "$assets" | grep -v '^[[:space:]]*$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Main execution
main() {
    parse_args "$@"
    trap cleanup EXIT

    # Create directories
    mkdir -p "$CACHE_DIR"

    # GitHub API URL
    if [ "$VERSION" = "latest" ]; then
        API_URL="https://api.github.com/repos/${REPO}/releases/latest"
    else
        API_URL="https://api.github.com/repos/${REPO}/releases/tags/${VERSION}"
    fi

    # Get release info
    echo "Fetching release info for ${REPO}..." >&2
    RELEASE_JSON=$(curl -sSL -H "Accept: application/vnd.github.v3+json" "$API_URL")

    # Check for errors
    if echo "$RELEASE_JSON" | grep -q '"message": "Not Found"'; then
        echo "Error: Repository or release not found: ${REPO}@${VERSION}" >&2
        exit 1
    fi

    # Extract all asset names and clean them
    ASSETS=$(echo "$RELEASE_JSON" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
    ASSETS=$(clean_asset_list "$ASSETS")
    
    if [ -z "$ASSETS" ]; then
        echo "Error: No assets found in release" >&2
        exit 1
    fi

    echo "Available assets:" >&2
    echo "$ASSETS" | sed 's/^/  - /' >&2

    # Find the best matching asset - Ubuntu first, then fallbacks
    ASSET_NAME=""
    UBUNTU_VERSION=$(detect_ubuntu_version)
    
    if [ -n "$UBUNTU_VERSION" ]; then
        echo "Detected Ubuntu version: $UBUNTU_VERSION" >&2
        # Priority 1: Exact Ubuntu version match (e.g., ubuntu24.04)
        ASSET_NAME=$(echo "$ASSETS" | grep -i "$UBUNTU_VERSION" | head -1)
        [ -n "$ASSET_NAME" ] && echo "Found exact Ubuntu match: $ASSET_NAME" >&2
    fi
    
    # Priority 2: Any Ubuntu match
    if [ -z "$ASSET_NAME" ]; then
        ASSET_NAME=$(echo "$ASSETS" | grep -i "ubuntu" | head -1)
        [ -n "$ASSET_NAME" ] && echo "Found Ubuntu match: $ASSET_NAME" >&2
    fi
    
    # Priority 3: Linux matches
    if [ -z "$ASSET_NAME" ]; then
        ASSET_NAME=$(echo "$ASSETS" | grep -i "linux" | head -1)
        [ -n "$ASSET_NAME" ] && echo "Found Linux match: $ASSET_NAME" >&2
    fi
    
    # Priority 4: First available asset
    if [ -z "$ASSET_NAME" ]; then
        ASSET_NAME=$(echo "$ASSETS" | head -1)
        echo "Using first available asset: $ASSET_NAME" >&2
    fi

    echo "Selected asset: $ASSET_NAME" >&2

    # Get download URL - try multiple approaches
    DOWNLOAD_URL=$(extract_download_url "$RELEASE_JSON" "$ASSET_NAME")
    
    if [ -z "$DOWNLOAD_URL" ]; then
        # Alternative approach: look for the URL pattern directly
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o "https://github.com/[^/]*/[^/]*/releases/download/[^\"]*$ASSET_NAME" | head -1)
    fi
    
    if [ -z "$DOWNLOAD_URL" ]; then
        echo "ERROR: Could not extract download URL for asset: $ASSET_NAME" >&2
        echo "Debug: Showing browser_download_url patterns found:" >&2
        echo "$RELEASE_JSON" | grep '"browser_download_url"' | head -3 >&2
        exit 1
    fi

    echo "Download URL: $DOWNLOAD_URL" >&2

    # Local file path
    LOCAL_FILE="${CACHE_DIR}/${REPO//\//_}_${ASSET_NAME}"

    # Download if needed
    if [ "$FORCE" = true ] || [ ! -f "$LOCAL_FILE" ]; then
        echo "Downloading ${ASSET_NAME}..." >&2
        curl -L -f -o "${LOCAL_FILE}.tmp" "$DOWNLOAD_URL" || {
            echo "Download failed: $DOWNLOAD_URL" >&2
            exit 1
        }
        mv "${LOCAL_FILE}.tmp" "$LOCAL_FILE"
        chmod +x "$LOCAL_FILE"
        echo "Download completed: $LOCAL_FILE" >&2
    else
        echo "Using cached version: $LOCAL_FILE" >&2
    fi

    # Execute the binary with all remaining arguments
    echo "Executing: $LOCAL_FILE ${ARGS[*]}" >&2
    exec "$LOCAL_FILE" "${ARGS[@]}"
}

# If script is being executed directly, run main
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
