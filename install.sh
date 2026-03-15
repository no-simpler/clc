#!/usr/bin/env bash
# install.sh — curl-based installer for clc (Claude Code Cloak)
# Usage: curl -fsSL https://github.com/no-simpler/clc/releases/latest/download/install.sh | bash

set -euo pipefail

REPO="no-simpler/clc"
BINARY_URL="https://github.com/${REPO}/releases/latest/download/clc.sh"

# ── Find install dir ───────────────────────────────────────────────────────────

find_install_dir() {
    # Build a lookup set of directories currently on $PATH
    local -A on_path=()
    local path_entries=()
    IFS=':' read -ra path_entries <<< "$PATH"
    for dir in "${path_entries[@]}"; do
        on_path["$dir"]=1
    done

    # Usual suspects in priority order — pick first that is on $PATH and writable
    local candidates=(
        "$HOME/.local/bin"
        "$HOME/bin"
        "/usr/local/bin"
        "/usr/bin"
        "/opt/local/bin"
        "/opt/homebrew/bin"
    )
    for dir in "${candidates[@]}"; do
        if [[ -n "${on_path[$dir]:-}" && -d "$dir" && -w "$dir" ]]; then
            echo "$dir"; return
        fi
    done

    # Create ~/.local/bin if it's referenced in $PATH but doesn't exist yet
    if [[ -n "${on_path[$HOME/.local/bin]:-}" && ! -e "$HOME/.local/bin" ]]; then
        mkdir -p "$HOME/.local/bin" && echo "$HOME/.local/bin"; return
    fi

    return 1
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
    echo "Installing clc..."

    local install_dir
    if ! install_dir=$(find_install_dir); then
        echo "Error: no suitable installation directory found." >&2
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
