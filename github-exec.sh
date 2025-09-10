#!/bin/bash
set -euo pipefail

# Default values
CACHE_DIR="${HOME}/.cache/github-exec"
CONFIG_DIR="${HOME}/.config/github-exec"
VERSION="latest"
FORCE=false

# Usage information
usage() {
    cat << EOF
github-exec - Execute binaries from GitHub releases

Usage: github-exec [OPTIONS] <user/repo> <executable> [args...]

Options:
  --version VERSION    Use specific version instead of latest
  --force              Force redownload
  --help               Show this help
  --cache-dir DIR      Custom cache directory (default: ~/.cache/github-exec)
  --no-cache           Disable caching

Examples:
  github-exec zacuke/run-node server.js
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
            --no-cache)
                CACHE_DIR="/tmp/github-exec-$$"
                shift
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

    if [ $# -lt 2 ]; then
        usage
    fi

    REPO="$1"
    EXECUTABLE="$2"
    shift 2
    ARGS=("$@")
}

# Clean up temporary cache
cleanup() {
    if [[ "$CACHE_DIR" == /tmp/github-exec-* ]]; then
        rm -rf "$CACHE_DIR" 2>/dev/null || true
    fi
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

    # Extract asset info
    ASSETS=$(echo "$RELEASE_JSON" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
    if [ -z "$ASSETS" ]; then
        echo "Error: No assets found in release" >&2
        exit 1
    fi

    # Find the best matching asset (prioritize Linux binaries)
    ASSET_NAME=""
    for asset in $ASSETS; do
        if [[ "$asset" == *linux* || "$asset" == *Linux* || \
              "$asset" == *amd64* || "$asset" == *x86_64* ]]; then
            ASSET_NAME="$asset"
            break
        fi
    done

    # Fallback to first asset if no Linux-specific one found
    if [ -z "$ASSET_NAME" ]; then
        ASSET_NAME=$(echo "$ASSETS" | head -1)
    fi

    # Get download URL (simple grep approach since we can't use jq)
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -A5 "\"name\": \"$ASSET_NAME\"" | \
                   grep '"browser_download_url"' | cut -d'"' -f4)

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "Error: Could not find download URL for asset: $ASSET_NAME" >&2
        exit 1
    fi

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
    fi

    # Execute the binary with all remaining arguments
    exec "$LOCAL_FILE" "${ARGS[@]}"
}

# If script is being executed directly, run main
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi