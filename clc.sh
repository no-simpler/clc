#!/usr/bin/env bash
# clc - Claude Code Cloak
# Obfuscates Claude Code usage in repositories where Claude-related files cannot be committed.

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────

CLC_VERSION="0.1.0"
CLC_STORE="${HOME}/.clc"

# ── Color / style ─────────────────────────────────────────────────────────────

# Populated by setup_color(); empty strings when color is disabled.
CLR_BOLD="" CLR_DIM="" CLR_RESET=""
CLR_SECTION="" CLR_KEY="" CLR_VAL="" CLR_MUTED=""

setup_color() {
    # Disable when NO_COLOR is set, --no-color was passed, or stdout is not a tty.
    if [[ -n "${NO_COLOR-}" || "${OPT_NO_COLOR}" == 1 || ! -t 1 ]]; then
        return
    fi
    CLR_BOLD=$'\e[1m'
    CLR_DIM=$'\e[2m'
    CLR_RESET=$'\e[0m'
    CLR_SECTION="${CLR_BOLD}"          # section headers
    CLR_KEY="${CLR_DIM}"               # label column
    CLR_VAL=""                         # value column (plain)
    CLR_MUTED="${CLR_DIM}"             # <none> / secondary info
}

# ── Helpers ───────────────────────────────────────────────────────────────────

die() { echo "clc: error: $*" >&2; exit 1; }
need_cmd() { command -v "$1" &>/dev/null || die "'$1' not found on PATH"; }

# Shorten a path by replacing $HOME prefix with ~.
short_path() { echo "${1/#${HOME}/\~}"; }

# Print a section header.
print_header() { echo "${CLR_SECTION}${1}${CLR_RESET}"; }

# Print a key/value info line with consistent label width.
info_line() { printf "  ${CLR_KEY}%-18s${CLR_RESET} ${CLR_VAL}%s${CLR_RESET}\n" "$1" "$2"; }

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

# List peer worktrees: worktrees whose path matches <parent>/<main-name>-<suffix>.
# Prints tab-separated lines: <worktree-path> <branch>
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

    print_header "Repository"
    local sp; sp=$(short_path "${main_worktree}")
    info_line "path:" "${sp%/*}/${CLR_BOLD}${sp##*/}${CLR_RESET}"

    local peers=()
    while IFS=$'\t' read -r wt_path wt_branch; do
        peers+=("${wt_path}	${wt_branch}")
    done < <(list_peer_worktrees "${main_worktree}")

    echo
    print_header "Managed peer worktrees"
    if [[ ${#peers[@]} -eq 0 ]]; then
        echo "  ${CLR_MUTED}<none>${CLR_RESET}"
    else
        local base; base=$(basename "${main_worktree}")
        for entry in "${peers[@]}"; do
            local p b sp wt_name
            p=${entry%%	*}
            b=${entry##*	}
            sp=$(short_path "${p}")
            # Worktree name is the part after "<base>-" in the directory name
            wt_name=${p##*/${base}-}
            # Display: dim path prefix, bold worktree-name, dim branch
            info_line "${wt_name}:" "${sp%/${base}-*}/${base}-${CLR_BOLD}${wt_name}${CLR_RESET} ${CLR_MUTED}(${b})${CLR_RESET}"
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
      --no-color  Disable colored output

Actions:
  status          Show repo info and managed worktrees (default)

Run 'clc' without arguments to view the current repository status.
EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────

main() {
    local action=""
    OPT_NO_COLOR=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)     usage; exit 0 ;;
            -V|--version)  echo "clc ${CLC_VERSION}"; exit 0 ;;
            --no-color)    OPT_NO_COLOR=1 ;;
            -*)            echo "clc: unknown option: $1" >&2
                           echo "Try 'clc --help' for usage." >&2; exit 1 ;;
            *)
                if [[ -z "${action}" ]]; then
                    action="$1"
                else
                    echo "clc: unexpected argument: $1" >&2
                    echo "Try 'clc --help' for usage." >&2; exit 1
                fi
                ;;
        esac
        shift
    done

    need_cmd git
    setup_color

    case "${action}" in
        ""|status) cmd_status ;;
        *) echo "clc: unknown action: ${action}" >&2
           echo "Try 'clc --help' for usage." >&2; exit 1 ;;
    esac
}

main "$@"
