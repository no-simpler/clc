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
CLR_SECTION="" CLR_KEY="" CLR_VAL="" CLR_MUTED="" CLR_WARN=""

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
    CLR_WARN=$'\e[1;33m'              # bold yellow for warnings
}

# ── Helpers ───────────────────────────────────────────────────────────────────

die() { echo "clc: error: $*" >&2; exit 1; }
need_cmd() { command -v "$1" &>/dev/null || die "'$1' not found on PATH"; }

# Shorten a path by replacing $HOME prefix with ~.
short_path() { echo "${1/#${HOME}/\~}"; }

# Print a section header with optional muted subtitle on the same line.
print_header() {
    local heading="$1" subtitle="${2-}"
    if [[ -n "${subtitle}" ]]; then
        echo "${CLR_BOLD}${heading}${CLR_RESET} ${subtitle}"
    else
        echo "${CLR_BOLD}${heading}${CLR_RESET}"
    fi
}


# ── Claude-file state detection ───────────────────────────────────────────────

# Exact patterns we look for in ignore files (slashes significant).
CLC_PAT_MD="CLAUDE.md"
CLC_PAT_DIR="/.claude/"

# Return 0 if any Claude-related files are tracked by git in the given worktree.
claude_files_tracked() {
    local wt="$1"
    git -C "${wt}" ls-files -- "CLAUDE.md" "*/CLAUDE.md" ".claude" 2>/dev/null | grep -q .
}

# Echo "yes", "partial", or "no" based on exact-line presence of both/one/neither
# CLC pattern in .git/info/exclude (uncommented = exact match, no leading #).
claude_local_ignore_state() {
    local main_gitdir="$1"
    local exclude_file="${main_gitdir}/info/exclude"
    local has_md=0 has_dir=0
    if [[ -f "${exclude_file}" ]]; then
        grep -qxF "${CLC_PAT_MD}"  "${exclude_file}" 2>/dev/null && has_md=1
        grep -qxF "${CLC_PAT_DIR}" "${exclude_file}" 2>/dev/null && has_dir=1
    fi
    if   [[ ${has_md} -eq 1 && ${has_dir} -eq 1 ]]; then echo "yes"
    elif [[ ${has_md} -eq 1 || ${has_dir} -eq 1 ]]; then echo "partial"
    else echo "no"
    fi
}

# Return 0 if any CLC pattern appears as an uncommented exact line in root .gitignore.
claude_in_gitignore() {
    local wt="$1"
    local gitignore="${wt}/.gitignore"
    [[ -f "${gitignore}" ]] || return 1
    grep -qxF "${CLC_PAT_MD}"  "${gitignore}" 2>/dev/null && return 0
    grep -qxF "${CLC_PAT_DIR}" "${gitignore}" 2>/dev/null && return 0
    return 1
}

# Print a warning line subordinate to the line above it.  Args: warning messages.
print_warning_line() {
    [[ $# -eq 0 ]] && return
    local msg="$1"; shift
    for w in "$@"; do msg+="; ${w}"; done
    printf "      %s%s%s\n" "${CLR_WARN}" "${msg}" "${CLR_RESET}"
}

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

        # Dirty if the worktree has any staged or unstaged changes
        local wt_dirty=""
        [[ -n "$(git -C "${wt_path}" status --porcelain 2>/dev/null)" ]] && wt_dirty="dirty"

        if [[ "${wt_path}" == "${main_worktree}" ]]; then
            printf "main\001main\001%s\001%s\001%s\n" "${wt_path}" "${wt_branch}" "${wt_dirty}"
        elif [[ "${wt_path}" == "${parent}/${base}-"* ]]; then
            local wt_name="${wt_path##*/${base}-}"
            printf "peer\001%s\001%s\001%s\001%s\n" "${wt_name}" "${wt_path}" "${wt_branch}" "${wt_dirty}"
        else
            printf "unmanaged\001\001%s\001%s\001%s\n" "${wt_path}" "${wt_branch}" "${wt_dirty}"
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

    # ── Claude-file state for current worktree ────────────────────────────────
    local state_tracked=0 state_ignore state_gitignore=0
    claude_files_tracked   "${current_worktree}"     && state_tracked=1
    state_ignore=$(claude_local_ignore_state "${main_gitdir}")
    claude_in_gitignore    "${current_worktree}"     && state_gitignore=1

    # Global golden-state flag (used by future commands).
    IS_GOLDEN=0
    [[ ${state_tracked} -eq 0 && "${state_ignore}" == "yes" && ${state_gitignore} -eq 0 ]] \
        && IS_GOLDEN=1

    # Warning buckets: main-worktree-level vs current-worktree-level.
    local -a main_warnings=() cur_warnings=()
    [[ "${state_ignore}" == "no"      ]] && main_warnings+=("Claude files not ignored")
    [[ "${state_ignore}" == "partial" ]] && main_warnings+=("Claude files only partially ignored")
    [[ ${state_tracked}    -eq 1     ]] && cur_warnings+=("Claude files detected")
    [[ ${state_gitignore}  -eq 1     ]] && cur_warnings+=("Claude files in .gitignore")

    # Collect worktrees by category
    local main_branch="<unknown>"
    local -a peer_rows=() unmanaged_rows=()
    local max_peer_name_len=0

    local main_dirty=""
    while IFS=$'\001' read -r type name path branch dirty; do
        case "${type}" in
            main)     main_branch="${branch}"; main_dirty="${dirty}" ;;
            peer)     peer_rows+=("${name}"$'\001'"${path}"$'\001'"${branch}"$'\001'"${dirty}")
                      [[ ${#name} -gt ${max_peer_name_len} ]] && max_peer_name_len=${#name} ;;
            unmanaged) unmanaged_rows+=("${path}"$'\001'"${branch}"$'\001'"${dirty}") ;;
        esac
    done < <(list_all_worktrees "${main_worktree}")

    # Compute max visible content width across all sections for branch alignment.
    # styled_path contains ANSI codes so use ${#sp} (visible length) for section 1.
    local sp_main; sp_main=$(short_path "${main_worktree}")
    local max_content_len=${#sp_main}
    [[ ${max_peer_name_len} -gt ${max_content_len} ]] && max_content_len=${max_peer_name_len}
    for row in "${unmanaged_rows[@]}"; do
        local u_path u_branch u_sp
        IFS=$'\001' read -r u_path u_branch <<< "${row}"
        u_sp=$(short_path "${u_path}")
        [[ ${#u_sp} -gt ${max_content_len} ]] && max_content_len=${#u_sp}
    done

    # Section 1: Repository & main worktree
    print_header "Repository"
    local sp styled_path main_pad
    sp="${sp_main}"
    styled_path="${sp%/*}/${CLR_BOLD}${sp##*/}${CLR_RESET}"
    main_pad=$(( max_content_len - ${#sp} ))
    local main_dirty_suffix=""
    [[ -n "${main_dirty}" ]] && main_dirty_suffix=" ${CLR_MUTED}(dirty)${CLR_RESET}"
    if [[ "${main_worktree}" == "${current_worktree}" ]]; then
        printf "  ${CLR_BOLD}*${CLR_RESET} %s%-*s  ${CLR_MUTED}(%s)${CLR_RESET}%s\n" \
            "${styled_path}" "${main_pad}" "" "${main_branch}" "${main_dirty_suffix}"
        # Combine main-level and current-level warnings (same line is both).
        local -a combined_warnings=()
        [[ ${#main_warnings[@]} -gt 0 ]] && combined_warnings+=("${main_warnings[@]}")
        [[ ${#cur_warnings[@]}  -gt 0 ]] && combined_warnings+=("${cur_warnings[@]}")
        if [[ ${#combined_warnings[@]} -gt 0 ]]; then print_warning_line "${combined_warnings[@]}"; fi
    else
        printf "    %s%-*s  ${CLR_MUTED}(%s)${CLR_RESET}%s\n" \
            "${styled_path}" "${main_pad}" "" "${main_branch}" "${main_dirty_suffix}"
        if [[ ${#main_warnings[@]} -gt 0 ]]; then print_warning_line "${main_warnings[@]}"; fi
    fi

    # Section 2: Managed worktrees
    local parent_dir; parent_dir=$(short_path "$(dirname "${main_worktree}")")
    echo
    print_header "Managed worktrees" "in ${parent_dir}"
    if [[ ${#peer_rows[@]} -eq 0 ]]; then
        echo "  ${CLR_MUTED}<none>${CLR_RESET}"
    else
        for row in "${peer_rows[@]}"; do
            local name path branch dirty dirty_suffix
            IFS=$'\001' read -r name path branch dirty <<< "${row}"
            dirty_suffix=""
            [[ -n "${dirty}" ]] && dirty_suffix=" ${CLR_MUTED}(dirty)${CLR_RESET}"
            if [[ "${path}" == "${current_worktree}" ]]; then
                printf "  ${CLR_BOLD}*${CLR_RESET} ${CLR_BOLD}%-*s${CLR_RESET}  ${CLR_MUTED}(%s)${CLR_RESET}%s\n" \
                    "${max_content_len}" "${name}" "${branch}" "${dirty_suffix}"
                if [[ ${#cur_warnings[@]} -gt 0 ]]; then print_warning_line "${cur_warnings[@]}"; fi
            else
                printf "    %-*s  ${CLR_MUTED}(%s)${CLR_RESET}%s\n" \
                    "${max_content_len}" "${name}" "${branch}" "${dirty_suffix}"
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
            local path branch dirty dirty_suffix
            IFS=$'\001' read -r path branch dirty <<< "${row}"
            sp=$(short_path "${path}")
            dirty_suffix=""
            [[ -n "${dirty}" ]] && dirty_suffix=" ${CLR_MUTED}(dirty)${CLR_RESET}"
            if [[ "${path}" == "${current_worktree}" ]]; then
                printf "  ${CLR_BOLD}*${CLR_RESET} %-*s  ${CLR_MUTED}(%s)${CLR_RESET}%s\n" \
                    "${max_content_len}" "${sp}" "${branch}" "${dirty_suffix}"
                if [[ ${#cur_warnings[@]} -gt 0 ]]; then print_warning_line "${cur_warnings[@]}"; fi
            else
                printf "    %-*s  ${CLR_MUTED}(%s)${CLR_RESET}%s\n" \
                    "${max_content_len}" "${sp}" "${branch}" "${dirty_suffix}"
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
