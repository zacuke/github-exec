#!/bin/bash
set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
BIN_PATH="${INSTALL_DIR}/github-exec"

echo "Uninstalling github-exec..."

# Remove the binary if it exists
if [[ -f "$BIN_PATH" ]]; then
    rm -f "$BIN_PATH"
    echo "Removed ${BIN_PATH}"
else
    echo "No binary found at ${BIN_PATH}"
fi

 
echo "Uninstall complete."