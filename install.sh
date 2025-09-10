#!/bin/bash
set -euo pipefail

GITHUB_EXEC_URL="https://raw.githubusercontent.com/zacuke/github-exec/main/github-exec.sh"
INSTALL_DIR="${HOME}/.local/bin"
BIN_PATH="${INSTALL_DIR}/github-exec"

echo "Installing github-exec..."
mkdir -p "$INSTALL_DIR"

# Download the script
if curl -sSL -o "$BIN_PATH" "$GITHUB_EXEC_URL"; then
    chmod +x "$BIN_PATH"
    echo "Successfully installed github-exec to ${BIN_PATH}"
    echo "Add to your PATH by adding this to your shell profile:"
    echo 'export PATH="${HOME}/.local/bin:$PATH"'
else
    echo "Failed to download github-exec" >&2
    exit 1
fi