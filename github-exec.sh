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

# Extract download URL from JSON for a specific asset name
extract_download_url() {
    local json="$1"
    local asset_name="$2"
    echo "$json" | grep -o "\"browser_download_url\": \"[^\"]*$asset_name[^\"]*\"" | \
    head -1 | \
    cut -d'"' -f4
}

# Clean asset names
clean_asset_list() {
    local assets="$1"
    echo "$assets" | grep -v '^[[:space:]]*$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Try to fetch a checksum file if available
get_checksum_for_asset() {
    local json="$1"
    local asset_name="$2"

    # Try to find a checksums.txt or .sha256 file
    local checksum_asset=$(echo "$json" | grep -o '"name": "[^"]*"' | cut -d'"' -f4 \
        | grep -i -E 'checksums?.txt|sha256' | head -1)

    if [ -n "$checksum_asset" ]; then
        local url=$(extract_download_url "$json" "$checksum_asset")
        if [ -n "$url" ]; then
            echo "Fetching checksum file: $checksum_asset" >&2
            local tmp=$(mktemp)
            curl -sSL -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
            # Try to extract a matching checksum for the asset
            local checksum=$(grep -i "$asset_name" "$tmp" | head -1 | awk '{print $1}')
            rm -f "$tmp"
            echo "$checksum"
            return 0
        fi
    fi
    return 1
}

# Main execution
main() {
    parse_args "$@"
    trap cleanup EXIT

    mkdir -p "$CACHE_DIR"

    # GitHub API URL
    if [ "$VERSION" = "latest" ]; then
        API_URL="https://api.github.com/repos/${REPO}/releases/latest"
    else
        API_URL="https://api.github.com/repos/${REPO}/releases/tags/${VERSION}"
    fi

    echo "Fetching release info for ${REPO}..." >&2
    RELEASE_JSON=$(curl -sSL -H "Accept: application/vnd.github.v3+json" "$API_URL")

    if echo "$RELEASE_JSON" | grep -q '"message": "Not Found"'; then
        echo "Error: Repository or release not found: ${REPO}@${VERSION}" >&2
        exit 1
    fi

    # Extract the release tag
    RELEASE_TAG=$(echo "$RELEASE_JSON" | grep -m1 '"tag_name":' | cut -d'"' -f4)

    # Extract assets
    ASSETS=$(echo "$RELEASE_JSON" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
    ASSETS=$(clean_asset_list "$ASSETS")
    [ -z "$ASSETS" ] && { echo "Error: No assets found in release" >&2; exit 1; }

    echo "Available assets:" >&2
    echo "$ASSETS" | sed 's/^/  - /' >&2

    # Find best asset
    ASSET_NAME=""
    UBUNTU_VERSION=$(detect_ubuntu_version)
    if [ -n "$UBUNTU_VERSION" ]; then
        ASSET_NAME=$(echo "$ASSETS" | grep -i "$UBUNTU_VERSION" | head -1)
    fi
    [ -z "$ASSET_NAME" ] && ASSET_NAME=$(echo "$ASSETS" | grep -i "ubuntu" | head -1)
    [ -z "$ASSET_NAME" ] && ASSET_NAME=$(echo "$ASSETS" | grep -i "linux" | head -1)
    [ -z "$ASSET_NAME" ] && ASSET_NAME=$(echo "$ASSETS" | head -1)

    echo "Selected asset: $ASSET_NAME" >&2

    DOWNLOAD_URL=$(extract_download_url "$RELEASE_JSON" "$ASSET_NAME")
    if [ -z "$DOWNLOAD_URL" ]; then
        echo "ERROR: Could not extract download URL for asset: $ASSET_NAME" >&2
        exit 1
    fi
    echo "Download URL: $DOWNLOAD_URL" >&2

    # File locations
    LOCAL_PREFIX="${CACHE_DIR}/${REPO//\//_}_${ASSET_NAME}"
    LOCAL_FILE="${LOCAL_PREFIX}.bin"
    VERSION_FILE="${LOCAL_PREFIX}.version"

    # Checksum retrieval
    EXPECTED_SHA=""
    EXPECTED_SHA=$(get_checksum_for_asset "$RELEASE_JSON" "$ASSET_NAME" || true)

    NEED_DOWNLOAD=false
    if [ "$FORCE" = true ] || [ ! -f "$LOCAL_FILE" ]; then
        NEED_DOWNLOAD=true
    elif [ "$VERSION" = "latest" ]; then
        if [ ! -f "$VERSION_FILE" ] || [ "$(cat "$VERSION_FILE")" != "$RELEASE_TAG" ]; then
            echo "Cached version mismatch, refreshing..." >&2
            NEED_DOWNLOAD=true
        fi
    fi

    if [ "$NEED_DOWNLOAD" = true ]; then
        echo "Downloading ${ASSET_NAME} ($RELEASE_TAG)..." >&2
        curl -L -f -o "${LOCAL_FILE}.tmp" "$DOWNLOAD_URL"
        if [ -n "$EXPECTED_SHA" ]; then
            echo "Validating checksum..." >&2
            ACTUAL_SHA=$(sha256sum "${LOCAL_FILE}.tmp" | awk '{print $1}')
            if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
                echo "ERROR: Checksum mismatch! Expected $EXPECTED_SHA but got $ACTUAL_SHA" >&2
                rm -f "${LOCAL_FILE}.tmp"
                exit 1
            fi
        fi
        mv "${LOCAL_FILE}.tmp" "$LOCAL_FILE"
        chmod +x "$LOCAL_FILE"
        echo "$RELEASE_TAG" > "$VERSION_FILE"
        echo "Download completed: $LOCAL_FILE" >&2
    else
        echo "Using cached version: $LOCAL_FILE" >&2
    fi

    # Execute binary
    echo "Executing: $LOCAL_FILE ${ARGS[*]}" >&2
    exec "$LOCAL_FILE" "${ARGS[@]}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi