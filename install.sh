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
    
    # Check if INSTALL_DIR is already in PATH
    if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
        echo "Adding ${INSTALL_DIR} to PATH..."
        
        # Detect shell and update appropriate profile
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
        
        # Add export to profile file
        if [[ "$SHELL_NAME" == "fish" ]]; then
            echo "set -gx PATH ${INSTALL_DIR} \$PATH" >> "$PROFILE_FILE"
        else
            echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "$PROFILE_FILE"
        fi
        
        echo "Added PATH export to ${PROFILE_FILE}"
        echo "Run 'source ${PROFILE_FILE}' or restart your shell to apply changes"
    else
        echo "${INSTALL_DIR} is already in your PATH"
    fi
else
    echo "Failed to download github-exec" >&2
    exit 1
fi