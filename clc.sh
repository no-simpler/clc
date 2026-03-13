#!/usr/bin/env bash
# clc - Claude Code Cloak
# Obfuscates Claude Code usage in repositories where Claude-related files cannot be committed.

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────

CLC_VERSION="0.1.0"
CLC_STORE="${HOME}/.clc"

# Claude-related files managed by clc:
#   CLAUDE.md  – project instructions (any depth in worktree)
#   .claude/   – settings, memory, commands (worktree root only)
CLC_CLAUDE_FILES=("CLAUDE.md")
CLC_CLAUDE_DIRS=(".claude")

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


# ── Git helpers ───────────────────────────────────────────────────────────────

# Resolve the main .git directory for the repo containing $PWD.
# For a peer worktree this is the commondir (the main repo's .git), not the worktree's .git file.
git_main_gitdir() {
    local git_dir common_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
    # Peer worktrees have a commondir file pointing to the main .git
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

# Absolute path of the main worktree root given its .git directory path.
git_main_worktree() {
    local main_gitdir="$1"
    dirname "${main_gitdir}"
}

# Absolute path of the current worktree root (the worktree $PWD belongs to).
git_current_worktree() {
    git rev-parse --show-toplevel 2>/dev/null
}

# ── Managed-worktree helpers ──────────────────────────────────────────────────

# Return 0 if the given worktree path is managed, 1 otherwise.
# Managed = IS the main worktree, OR follows <parent>/<main-name>-<suffix>.
is_managed_worktree() {
    local wt_path="$1" main_worktree="$2"
    [[ "${wt_path}" == "${main_worktree}" ]] && return 0
    local parent base
    parent=$(dirname "${main_worktree}")
    base=$(basename "${main_worktree}")
    [[ "${wt_path}" == "${parent}/${base}-"* ]]
}

# List all worktrees for the repo.
# Prints tab-separated lines: <type>\t<name>\t<path>\t<branch>
# type   = "main" | "peer" | "unmanaged"
# name   = "main" for main; suffix after "<base>-" for peers; empty for unmanaged
# branch = branch name, "<detached>", or "<unknown>"
list_all_worktrees() {
    local main_worktree="$1"
    local parent base
    parent=$(dirname "${main_worktree}")
    base=$(basename "${main_worktree}")

    # git worktree list output: <path> <hash> [<branch>]  (or "(HEAD detached ...)")
    while IFS= read -r line; do
        local wt_path wt_branch
        wt_path=$(awk '{print $1}' <<< "${line}")
        if [[ "${line}" =~ \[([^\]]+)\] ]]; then
            wt_branch="${BASH_REMATCH[1]}"
        elif [[ "${line}" =~ \(detached\ HEAD ]]; then
            wt_branch="<detached>"
        else
            wt_branch="<unknown>"
        fi

        if [[ "${wt_path}" == "${main_worktree}" ]]; then
            printf "main\001main\001%s\001%s\n" "${wt_path}" "${wt_branch}"
        elif [[ "${wt_path}" == "${parent}/${base}-"* ]]; then
            local wt_name="${wt_path##*/${base}-}"
            printf "peer\001%s\001%s\001%s\n" "${wt_name}" "${wt_path}" "${wt_branch}"
        else
            printf "unmanaged\001\001%s\001%s\n" "${wt_path}" "${wt_branch}"
        fi
    done < <(git -C "${main_worktree}" worktree list 2>/dev/null)
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_status() {
    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)    || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                      || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                      || die "unable to determine current worktree"

    # Collect worktrees by category
    local main_branch="<unknown>"
    local -a peer_rows=() unmanaged_rows=()
    local max_peer_name_len=0

    while IFS=$'\001' read -r type name path branch; do
        case "${type}" in
            main)     main_branch="${branch}" ;;
            peer)     peer_rows+=("${name}"$'\001'"${path}"$'\001'"${branch}")
                      [[ ${#name} -gt ${max_peer_name_len} ]] && max_peer_name_len=${#name} ;;
            unmanaged) unmanaged_rows+=("${path}"$'\001'"${branch}") ;;
        esac
    done < <(list_all_worktrees "${main_worktree}")

    # Section 1: Repository & main worktree
    print_header "Repository"
    local sp; sp=$(short_path "${main_worktree}")
    local styled_path="${sp%/*}/${CLR_BOLD}${sp##*/}${CLR_RESET}"
    if [[ "${main_worktree}" == "${current_worktree}" ]]; then
        printf "  ${CLR_BOLD}*${CLR_RESET} %s  ${CLR_MUTED}(%s)${CLR_RESET}\n" "${styled_path}" "${main_branch}"
    else
        printf "    %s  ${CLR_MUTED}(%s)${CLR_RESET}\n" "${styled_path}" "${main_branch}"
    fi

    # Section 2: Managed peer worktrees
    echo
    print_header "Managed peer worktrees"
    if [[ ${#peer_rows[@]} -eq 0 ]]; then
        echo "  ${CLR_MUTED}<none>${CLR_RESET}"
    else
        for row in "${peer_rows[@]}"; do
            local name path branch padded
            IFS=$'\001' read -r name path branch <<< "${row}"
            padded=$(printf "%-${max_peer_name_len}s" "${name}")
            sp=$(short_path "${path}")
            if [[ "${path}" == "${current_worktree}" ]]; then
                printf "  ${CLR_BOLD}*${CLR_RESET} ${CLR_BOLD}%s${CLR_RESET}  %s  ${CLR_MUTED}(%s)${CLR_RESET}\n" \
                    "${padded}" "${sp}" "${branch}"
            else
                printf "    %s  %s  ${CLR_MUTED}(%s)${CLR_RESET}\n" \
                    "${padded}" "${sp}" "${branch}"
            fi
        done
    fi

    # Section 3: Unmanaged worktrees
    echo
    print_header "Unmanaged worktrees"
    if [[ ${#unmanaged_rows[@]} -eq 0 ]]; then
        echo "  ${CLR_MUTED}<none>${CLR_RESET}"
    else
        for row in "${unmanaged_rows[@]}"; do
            local path branch
            IFS=$'\001' read -r path branch <<< "${row}"
            sp=$(short_path "${path}")
            if [[ "${path}" == "${current_worktree}" ]]; then
                printf "  ${CLR_BOLD}*${CLR_RESET} %s  ${CLR_MUTED}(%s)${CLR_RESET}\n" \
                    "${sp}" "${branch}"
            else
                printf "    %s  ${CLR_MUTED}(%s)${CLR_RESET}\n" \
                    "${sp}" "${branch}"
            fi
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
  status          Show repository info and managed worktrees (default)

Claude-related files managed by clc:
  CLAUDE.md (any depth), .claude/ (worktree root only)

Only managed worktrees are supported. A worktree is managed if it is the main
worktree or a peer worktree at <parent>/<main-name>-<worktree-name>.

Run 'clc' without arguments to view repository and worktree status.
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
