#!/usr/bin/env bash
# install.sh — curl-based installer for clc (Claude Code Cloak)
# Usage: curl -fsSL https://github.com/no-simpler/clc/releases/latest/download/install.sh | bash

set -euo pipefail

REPO="no-simpler/clc"
BINARY_URL="https://github.com/${REPO}/releases/latest/download/clc.sh"

# ── Find install dir ───────────────────────────────────────────────────────────

find_install_dir() {
    # Prefer ~/.local/bin, then /usr/local/bin, then first writable $PATH entry
    local candidates=("$HOME/.local/bin" "/usr/local/bin")
    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" && -w "$dir" ]]; then
            echo "$dir"; return
        fi
    done
    # Create ~/.local/bin if it doesn't exist
    if [[ ! -e "$HOME/.local/bin" ]]; then
        mkdir -p "$HOME/.local/bin" && echo "$HOME/.local/bin"; return
    fi
    # Fall back to first writable entry on $PATH
    IFS=':' read -ra path_entries <<< "$PATH"
    for dir in "${path_entries[@]}"; do
        if [[ -d "$dir" && -w "$dir" ]]; then
            echo "$dir"; return
        fi
    done
    return 1
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
    echo "Installing clc..."

    local install_dir
    if ! install_dir=$(find_install_dir); then
        echo "Error: no writable directory found on \$PATH." >&2
        echo "Create ~/.local/bin and add it to your PATH, then re-run." >&2
        exit 1
    fi

    local dest="${install_dir}/clc"

    echo "  Downloading clc.sh from GitHub releases..."
    curl -fsSL "$BINARY_URL" -o "$dest"
    chmod +x "$dest"

    echo "  Installed: ${dest}"

    # Verify
    if command -v clc &>/dev/null; then
        echo "  Version:   $(clc --version)"
    else
        echo ""
        echo "Note: '${install_dir}' may not be on your current PATH."
        echo "Add it to your shell profile (e.g. export PATH=\"\$HOME/.local/bin:\$PATH\")."
    fi

    echo ""
    echo "Done. Run 'clc --help' to get started."
}

main "$@"
