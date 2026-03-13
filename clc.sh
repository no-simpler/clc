#!/usr/bin/env bash
# clc - Claude Code Cloak
# Obfuscates Claude Code usage in repositories where Claude-related files cannot be committed.

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────

CLC_VERSION="0.1.0"
CLC_STORE="${HOME}/.clc"

# ── Helpers ───────────────────────────────────────────────────────────────────

die() { echo "clc: error: $*" >&2; exit 1; }
need_cmd() { command -v "$1" &>/dev/null || die "'$1' not found on PATH"; }

# Print formatted key/value info line.
info_line() { printf "  %-20s %s\n" "$1" "$2"; }

# ── Git helpers ───────────────────────────────────────────────────────────────

# Resolve the main .git directory for the repo containing $PWD.
# For a worktree this is the commondir (the main repo's .git), not the worktree's .git file.
git_main_path() {
    local git_dir common_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
    # Worktrees have a commondir file pointing to the main .git
    if [[ -f "${git_dir}/commondir" ]]; then
        common_dir=$(cat "${git_dir}/commondir")
        # commondir may be relative to git_dir
        if [[ "${common_dir}" != /* ]]; then
            common_dir="${git_dir}/${common_dir}"
        fi
        realpath "${common_dir}"
    else
        realpath "${git_dir}"
    fi
}

# Absolute path of the repo's work tree root (main worktree).
git_main_worktree() {
    local main_path="$1"
    git --git-dir="${main_path}" rev-parse --show-toplevel 2>/dev/null
}

# List peer worktrees: worktrees whose path matches <parent>/<main-name>-<suffix>
# Prints lines of: <worktree-path> <branch>
list_peer_worktrees() {
    local main_worktree="$1"
    local parent base
    parent=$(dirname "${main_worktree}")
    base=$(basename "${main_worktree}")

    # git worktree list output: <path> <hash> [<branch>]
    while IFS= read -r line; do
        local wt_path wt_branch
        wt_path=$(awk '{print $1}' <<< "${line}")
        wt_branch=$(awk '{print $3}' <<< "${line}" | tr -d '[]')

        # Skip main worktree itself
        [[ "${wt_path}" == "${main_worktree}" ]] && continue

        # Only include managed peers: <parent>/<base>-<anything>
        if [[ "${wt_path}" == "${parent}/${base}-"* ]]; then
            printf "%s\t%s\n" "${wt_path}" "${wt_branch}"
        fi
    done < <(git -C "${main_worktree}" worktree list 2>/dev/null)
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_status() {
    local main_path main_worktree

    main_path=$(git_main_path) || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_path}") \
        || die "unable to determine main worktree"

    echo "Repository"
    info_line "main path:" "${main_path}"
    info_line "worktree:" "${main_worktree}"

    local peers=()
    while IFS=$'\t' read -r wt_path wt_branch; do
        peers+=("${wt_path}|${wt_branch}")
    done < <(list_peer_worktrees "${main_worktree}")

    echo
    if [[ ${#peers[@]} -eq 0 ]]; then
        echo "Managed peer worktrees: none"
    else
        echo "Managed peer worktrees"
        for entry in "${peers[@]}"; do
            local p b
            p=${entry%%|*}
            b=${entry##*|}
            info_line "$(basename "${p}"):" "${p} (${b})"
        done
    fi
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
clc ${CLC_VERSION} - Claude Code Cloak

Usage: clc [options] [action]

Options:
  -h, --help      Show this help and exit
  -V, --version   Show version and exit

Actions:
  status          Show repo info and managed worktrees (default)

Run 'clc' without arguments to view the current repository status.
EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────

main() {
    local action=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    usage; exit 0 ;;
            -V|--version) echo "clc ${CLC_VERSION}"; exit 0 ;;
            -*)           echo "clc: unknown option: $1" >&2; echo "Try 'clc --help' for usage." >&2; exit 1 ;;
            *)
                if [[ -z "${action}" ]]; then
                    action="$1"
                else
                    echo "clc: unexpected argument: $1" >&2; echo "Try 'clc --help' for usage." >&2; exit 1
                fi
                ;;
        esac
        shift
    done

    need_cmd git

    case "${action}" in
        ""|status) cmd_status ;;
        *) echo "clc: unknown action: ${action}" >&2; echo "Try 'clc --help' for usage." >&2; exit 1 ;;
    esac
}

main "$@"
