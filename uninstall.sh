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

# Detect shell profile
SHELL_NAME=$(basename "$SHELL")
case "$SHELL_NAME" in
    bash)
        PROFILE_FILE="${HOME}/.bashrc"
        ;;
    zsh)
        PROFILE_FILE="${HOME}/.zshrc"
        ;;
    fish)
        PROFILE_FILE="${HOME}/.config/fish/config.fish"
        ;;
    *)
        PROFILE_FILE="${HOME}/.profile"
        ;;
esac

if [[ -f "$PROFILE_FILE" ]]; then
    echo "Cleaning PATH modification in ${PROFILE_FILE}..."
    if [[ "$SHELL_NAME" == "fish" ]]; then
        sed -i '/set -gx PATH .*\.local\/bin/d' "$PROFILE_FILE"
    else
        sed -i '/export PATH=.*\.local\/bin.*$/d' "$PROFILE_FILE"
    fi
    echo "Removed github-exec PATH entry from ${PROFILE_FILE}"
fi

echo "Uninstall complete. You may restart your shell or run 'source ${PROFILE_FILE}' to finalize changes."