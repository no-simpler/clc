#!/usr/bin/env bash
# clc - Claude Code Cloak
# Obfuscates Claude Code usage in repositories where Claude-related files cannot be committed.
[[ "${BASH_VERSINFO[0]}" -lt 4 ]] && { echo "clc: error: Bash 4.0 or later required (found ${BASH_VERSION})" >&2; exit 1; }

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────

CLC_VERSION="0.1.0"
CLC_STORE="${CLC_STORE:-${HOME}/.clc}"

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

# ── Claude-file helpers ───────────────────────────────────────────────────────

# Return 0 if a relative path (file or dir) in the given worktree is git-managed:
# tracked/staged, or untracked but not ignored (visible to git).
_claude_item_git_managed() {
    local wt="$1" rel="${2%/}"  # strip trailing slash for git path matching
    git -C "${wt}" ls-files -- "${rel}" 2>/dev/null | grep -q . && return 0
    git -C "${wt}" ls-files --others --exclude-standard -- "${rel}" 2>/dev/null | grep -q . && return 0
    return 1
}

# ── Storage helpers ───────────────────────────────────────────────────────────

# Cross-platform md5 hash of a string.
md5_str() {
    if command -v md5sum &>/dev/null; then
        printf '%s' "$1" | md5sum | awk '{print $1}'
    else
        printf '%s' "$1" | md5 -q
    fi
}

# Return the base save directory for a repo: ~/.clc/saved/<name>@<md5-of-path>
repo_save_base() {
    local resolved; resolved=$(realpath "$1")
    echo "${CLC_STORE}/saved/$(basename "${resolved}")@$(md5_str "${resolved}")"
}

# Print relative paths of all Claude files in a directory (sorted, unique).
collect_claude_files_in_dir() {
    local base="$1"
    local -a results=()
    if [[ -d "${base}/.claude" ]]; then
        while IFS= read -r f; do results+=("${f#${base}/}"); done \
            < <(find "${base}/.claude" -type f 2>/dev/null | sort)
    fi
    while IFS= read -r f; do results+=("${f#${base}/}"); done \
        < <(find "${base}" -name "CLAUDE.md" -not -path "*/.git/*" -type f 2>/dev/null | sort)
    [[ ${#results[@]} -eq 0 ]] && return
    printf '%s\n' "${results[@]}" | sort -u
}

# Return the most recent timestamp subdirectory under save_base, or empty string.
latest_save_dir() {
    local save_base="$1"
    [[ -d "${save_base}" ]] || return 0
    local latest; latest=$(ls "${save_base}" 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -1)
    [[ -n "${latest}" ]] && echo "${save_base}/${latest}"
}

# Global arrays populated by _compare_claude_files.
_CMP_ONLY_STORAGE=()
_CMP_DIFFERENT=()
_CMP_ONLY_WORKTREE=()
_CMP_SAME=()

# Populate the four _CMP_* globals by comparing worktree wt against save_dir.
_compare_claude_files() {
    local wt="$1" save_dir="$2"
    _CMP_ONLY_STORAGE=()
    _CMP_DIFFERENT=()
    _CMP_ONLY_WORKTREE=()
    _CMP_SAME=()

    local -a wt_files=() storage_files=()
    while IFS= read -r f; do wt_files+=("$f"); done \
        < <(collect_claude_files_in_dir "${wt}")
    while IFS= read -r f; do storage_files+=("$f"); done \
        < <(collect_claude_files_in_dir "${save_dir}")

    local -A wt_set storage_set
    wt_set=(); storage_set=()
    for f in ${wt_files[@]+"${wt_files[@]}"}; do wt_set["$f"]=1; done
    for f in ${storage_files[@]+"${storage_files[@]}"}; do storage_set["$f"]=1; done

    for f in ${storage_files[@]+"${storage_files[@]}"}; do
        if [[ -z "${wt_set[$f]+x}" ]]; then
            _CMP_ONLY_STORAGE+=("$f")
        elif cmp -s "${wt}/${f}" "${save_dir}/${f}"; then
            _CMP_SAME+=("$f")
        else
            _CMP_DIFFERENT+=("$f")
        fi
    done
    for f in ${wt_files[@]+"${wt_files[@]}"}; do
        if [[ -z "${storage_set[$f]+x}" ]]; then
            _CMP_ONLY_WORKTREE+=("$f")
        fi
    done
}

# Apply restore from save_dir into wt using pre-populated _CMP_* globals.
# Prompts only for destructive operations (different content, file only in worktree).
# Non-destructive additions (file only in storage) are applied silently.
# Returns 1 if user aborts; 0 on success.
_apply_restore() {
    local wt="$1" save_dir="$2"
    local destructive_diffs=$(( ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} ))

    _print_compare_output

    if [[ ${destructive_diffs} -gt 0 ]]; then
        printf "\nSynchronize? (Data loss possible!) [y/N] "
        read -r response || response="n"
        echo
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            return 1
        fi
    fi

    for f in ${_CMP_ONLY_STORAGE[@]+"${_CMP_ONLY_STORAGE[@]}"}; do
        mkdir -p "$(dirname "${wt}/${f}")"
        cp "${save_dir}/${f}" "${wt}/${f}"
    done
    for f in ${_CMP_DIFFERENT[@]+"${_CMP_DIFFERENT[@]}"}; do
        mkdir -p "$(dirname "${wt}/${f}")"
        cp "${save_dir}/${f}" "${wt}/${f}"
    done
    for f in ${_CMP_ONLY_WORKTREE[@]+"${_CMP_ONLY_WORKTREE[@]}"}; do
        rm -f "${wt}/${f}"
    done
    echo "Synchronized."
}

# Print compare diff sections using the current _CMP_* globals.
_print_compare_output() {
    print_header "Compare"
    if [[ ${#_CMP_ONLY_STORAGE[@]} -gt 0 ]]; then
        echo "  Exists in storage only:"
        for f in "${_CMP_ONLY_STORAGE[@]}"; do printf "    + %s\n" "$f"; done
    fi
    if [[ ${#_CMP_DIFFERENT[@]} -gt 0 ]]; then
        echo "  Different content:"
        for f in "${_CMP_DIFFERENT[@]}"; do printf "    ~ %s\n" "$f"; done
    fi
    if [[ ${#_CMP_ONLY_WORKTREE[@]} -gt 0 ]]; then
        echo "  Exists in worktree only:"
        for f in "${_CMP_ONLY_WORKTREE[@]}"; do printf "    - %s\n" "$f"; done
    fi
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_save() {
    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)       || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                         || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                         || die "unable to determine current worktree"

    local save_base; save_base=$(repo_save_base "${main_worktree}")
    local -a files=()
    while IFS= read -r f; do files+=("$f"); done \
        < <(collect_claude_files_in_dir "${current_worktree}")

    local dest_dir="${save_base}/$(date +%s)"
    mkdir -p "${dest_dir}"
    # Record the full path used for the hash, for discoverability when browsing storage.
    printf '%s\n' "$(realpath "${main_worktree}")" > "${save_base}/full-path.txt"
    for f in ${files[@]+"${files[@]}"}; do
        mkdir -p "$(dirname "${dest_dir}/${f}")"
        cp "${current_worktree}/${f}" "${dest_dir}/${f}"
    done

    print_header "Saved"
    printf "  %s\n" "$(short_path "${dest_dir}")"
    printf "  %d file(s)\n" "${#files[@]}"
}

cmd_compare() {
    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)       || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                         || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                         || die "unable to determine current worktree"

    local save_base; save_base=$(repo_save_base "${main_worktree}")
    local save_dir; save_dir=$(latest_save_dir "${save_base}")
    [[ -n "${save_dir}" ]] || die "no saved state found — run 'clc save' first"

    _compare_claude_files "${current_worktree}" "${save_dir}"
    local total=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} + ${#_CMP_SAME[@]} ))
    local diffs=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} ))

    if [[ ${diffs} -eq 0 ]]; then
        echo "All ${total} Claude file(s) in current worktree are in sync with storage."
        return 0
    fi

    _print_compare_output
    echo
    echo "Run 'clc save' to save current state; run 'clc restore' to load saved state."
    return 1
}

cmd_restore() {
    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)       || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                         || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                         || die "unable to determine current worktree"

    local save_base; save_base=$(repo_save_base "${main_worktree}")
    local save_dir; save_dir=$(latest_save_dir "${save_base}")
    [[ -n "${save_dir}" ]] || die "no saved state found — run 'clc save' first"

    _compare_claude_files "${current_worktree}" "${save_dir}"
    local total=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} + ${#_CMP_SAME[@]} ))
    local diffs=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} ))

    if [[ ${diffs} -eq 0 ]]; then
        echo "All ${total} Claude file(s) in current worktree are in sync with storage."
        return 0
    fi

    _apply_restore "${current_worktree}" "${save_dir}"
}

cmd_new() {
    local opt_with_claude=0 full_name="" branch=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--with-claude) opt_with_claude=1 ;;
            -*) die "unknown option for 'new': $1" ;;
            *)  if   [[ -z "${full_name}" ]]; then full_name="$1"
                elif [[ -z "${branch}"    ]]; then branch="$1"
                else die "unexpected argument: $1"
                fi ;;
        esac
        shift
    done
    [[ -n "${full_name}" ]] || die "usage: clc new [-c] <name> [<branch>]"

    # Derive worktree name: last slash-component, then strip leading ticket prefix.
    local name="${full_name##*/}"
    if [[ "${name}" =~ ^[A-Z]+-[0-9]+[-_]+(.+)$ ]]; then
        name="${BASH_REMATCH[1]}"
    fi
    [[ "${name}" =~ ^[a-zA-Z0-9]+([-_][a-zA-Z0-9]+)*$ ]] \
        || die "invalid worktree name derived from '${full_name}': '${name}'"

    # Branch: explicit arg → full first arg.
    [[ -z "${branch}" ]] && branch="${full_name}"

    local main_gitdir main_worktree
    main_gitdir=$(git_main_gitdir)       || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                         || die "unable to determine main worktree"

    local parent base new_path
    parent=$(dirname "${main_worktree}")
    base=$(basename "${main_worktree}")
    new_path="${parent}/${base}-${name}"

    [[ -e "${new_path}" ]] && die "directory already exists: ${new_path}"

    # Check out existing branch or create a new one.
    if git -C "${main_worktree}" rev-parse --verify "refs/heads/${branch}" >/dev/null 2>&1; then
        git -C "${main_worktree}" worktree add "${new_path}" "${branch}" >/dev/null 2>&1 \
            || die "failed to create worktree '${name}' on branch '${branch}' (already checked out elsewhere?)"
    else
        git -C "${main_worktree}" worktree add "${new_path}" -b "${branch}" >/dev/null 2>&1 \
            || die "failed to create worktree '${name}' with new branch '${branch}'"
    fi

    print_header "Created"
    printf "  %s  %s(%s)%s\n" "$(short_path "${new_path}")" "${CLR_MUTED}" "${branch}" "${CLR_RESET}"
    echo

    if [[ ${opt_with_claude} -eq 1 ]]; then
        local save_base; save_base=$(repo_save_base "${main_worktree}")
        local save_dir; save_dir=$(latest_save_dir "${save_base}")
        if [[ -n "${save_dir}" ]]; then
            _compare_claude_files "${new_path}" "${save_dir}"
            local total=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} + ${#_CMP_SAME[@]} ))
            local diffs=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} ))
            if [[ ${diffs} -eq 0 ]]; then
                echo "All ${total} Claude file(s) in new worktree are in sync with storage."
                echo
            else
                _apply_restore "${new_path}" "${save_dir}" || true
                echo
            fi
        else
            echo "${CLR_MUTED}(no saved state — run 'clc save' to save Claude files first)${CLR_RESET}"
            echo
        fi
    fi

    cmd_status
}

cmd_rm() {
    local opt_with_branch=0 name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--with-branch) opt_with_branch=1 ;;
            -*) die "unknown option for 'rm': $1" ;;
            *)  if [[ -z "${name}" ]]; then name="$1"
                else die "unexpected argument: $1"
                fi ;;
        esac
        shift
    done
    [[ -n "${name}" ]] || die "usage: clc rm [-b] <name>"

    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)    || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                      || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                      || die "unable to determine current worktree"

    # Find the peer by name.
    local wt_path="" wt_branch="" wt_dirty=""
    while IFS=$'\001' read -r type row_name path branch dirty; do
        if [[ "${type}" == "peer" && "${row_name}" == "${name}" ]]; then
            wt_path="${path}"; wt_branch="${branch}"; wt_dirty="${dirty}"
            break
        fi
    done < <(list_all_worktrees "${main_worktree}")

    [[ -n "${wt_path}" ]]                          || die "no managed peer worktree named '${name}'"
    [[ "${wt_path}" != "${current_worktree}" ]]    || die "cannot remove current worktree '${name}'"
    [[ -z "${wt_dirty}" ]]                         || die "worktree '${name}' has uncommitted changes"

    git -C "${main_worktree}" worktree remove "${wt_path}" >/dev/null 2>&1 \
        || die "failed to remove worktree '${name}'"
    [[ -d "${wt_path}" ]] && rm -rf "${wt_path}"

    print_header "Removed"
    printf "  %s  %s(%s)%s\n" "$(short_path "${wt_path}")" "${CLR_MUTED}" "${wt_branch}" "${CLR_RESET}"
    if [[ ${opt_with_branch} -eq 1 ]]; then
        git -C "${main_worktree}" branch -d "${wt_branch}" >/dev/null 2>&1 \
            || print_warning_line "branch '${wt_branch}' not deleted — not fully merged"
    fi
    echo

    cmd_status
}

cmd_prune() {
    local opt_with_branch=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--with-branch) opt_with_branch=1 ;;
            -*) die "unknown option for 'prune': $1" ;;
            *)  die "unexpected argument: $1" ;;
        esac
        shift
    done

    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)    || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                      || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                      || die "unable to determine current worktree"

    # Collect eligible peers first so we can print "(nothing to prune)" before touching anything.
    local -a to_remove=()
    while IFS=$'\001' read -r type name path branch dirty; do
        [[ "${type}" == "peer" ]]                || continue
        [[ "${path}" != "${current_worktree}" ]] || continue
        [[ -z "${dirty}" ]]                      || continue
        to_remove+=("${name}"$'\001'"${path}"$'\001'"${branch}")
    done < <(list_all_worktrees "${main_worktree}")

    print_header "Pruned"
    if [[ ${#to_remove[@]} -eq 0 ]]; then
        echo "  ${CLR_MUTED}(nothing to prune)${CLR_RESET}"
    else
        for row in "${to_remove[@]}"; do
            local r_name r_path r_branch
            IFS=$'\001' read -r r_name r_path r_branch <<< "${row}"
            git -C "${main_worktree}" worktree remove "${r_path}" >/dev/null 2>&1 \
                || die "failed to remove worktree '${r_name}'"
            [[ -d "${r_path}" ]] && rm -rf "${r_path}"
            echo "  - ${r_name}  ${CLR_MUTED}(${r_branch})${CLR_RESET}"
            if [[ ${opt_with_branch} -eq 1 ]]; then
                git -C "${main_worktree}" branch -d "${r_branch}" >/dev/null 2>&1 \
                    || print_warning_line "branch '${r_branch}' not deleted — not fully merged"
            fi
        done
    fi
    echo

    cmd_status
}

cmd_ignore() {
    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)         || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                           || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                           || die "unable to determine current worktree"

    local exclude_file="${main_gitdir}/info/exclude"
    mkdir -p "${main_gitdir}/info"
    [[ -f "${exclude_file}" ]] || touch "${exclude_file}"

    local -a added=()
    for pat in "${CLC_PAT_MD}" "${CLC_PAT_DIR}"; do
        if ! grep -qxF "${pat}" "${exclude_file}" 2>/dev/null; then
            echo "${pat}" >> "${exclude_file}"
            added+=("${pat}")
        fi
    done

    print_header "Ignored"
    if [[ ${#added[@]} -eq 0 ]]; then
        echo "  ${CLR_MUTED}(already up to date)${CLR_RESET}"
    else
        for pat in "${added[@]}"; do echo "  + ${pat}"; done
    fi
    echo

    cmd_status
}

cmd_unignore() {
    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)         || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                           || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                           || die "unable to determine current worktree"

    local exclude_file="${main_gitdir}/info/exclude"
    local -a removed=()

    if [[ -f "${exclude_file}" ]]; then
        for pat in "${CLC_PAT_MD}" "${CLC_PAT_DIR}"; do
            if grep -qxF "${pat}" "${exclude_file}" 2>/dev/null; then
                grep -vxF "${pat}" "${exclude_file}" > "${exclude_file}.tmp" || true
                mv "${exclude_file}.tmp" "${exclude_file}"
                removed+=("${pat}")
            fi
        done
    fi

    print_header "Unignored"
    if [[ ${#removed[@]} -eq 0 ]]; then
        echo "  ${CLR_MUTED}(nothing to remove)${CLR_RESET}"
    else
        for pat in "${removed[@]}"; do echo "  - ${pat}"; done
    fi
    echo

    cmd_status
}

cmd_ls() {
    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)    || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                      || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                      || die "unable to determine current worktree"

    # Show a transient "Searching..." prompt on TTY so the user knows work is happening.
    # Skipped when stdout is not a TTY (pipes, test capture) — output stays clean.
    [[ -t 1 ]] && printf "Searching..."

    local -a items=()

    # .claude/ at worktree root
    [[ -d "${current_worktree}/.claude" ]] && items+=(".claude/")

    # All CLAUDE.md files at any depth, sorted by path
    while IFS= read -r abs_path; do
        items+=("${abs_path#${current_worktree}/}")
    done < <(find "${current_worktree}" -name "CLAUDE.md" -not -path "*/.git/*" 2>/dev/null | sort)

    # Clear the "Searching..." line, then print the real header
    [[ -t 1 ]] && printf "\r\033[K"
    print_header "Claude files"

    if [[ ${#items[@]} -eq 0 ]]; then
        echo "  ${CLR_MUTED}<none>${CLR_RESET}"
    else
        for rel in "${items[@]}"; do
            if _claude_item_git_managed "${current_worktree}" "${rel}"; then
                printf "  %s!%s %s%s%s\n" "${CLR_WARN}" "${CLR_RESET}" "${CLR_WARN}" "${rel}" "${CLR_RESET}"
            else
                printf "    %s  %s(properly ignored)%s\n" "${rel}" "${CLR_MUTED}" "${CLR_RESET}"
            fi
        done
    fi

    # Storage comparison
    local save_base; save_base=$(repo_save_base "${main_worktree}")
    local save_dir; save_dir=$(latest_save_dir "${save_base}")
    echo
    if [[ -z "${save_dir}" ]]; then
        echo "${CLR_MUTED}(no saved state — run 'clc save')${CLR_RESET}"
    else
        _compare_claude_files "${current_worktree}" "${save_dir}"
        local total=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} + ${#_CMP_SAME[@]} ))
        local diffs=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} ))
        if [[ ${diffs} -eq 0 ]]; then
            echo "All ${total} Claude file(s) are in sync with storage."
        else
            _print_compare_output
            echo
            echo "Run 'clc save' to save current state; run 'clc restore' to load saved state."
        fi
    fi
}

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
  status                 Show repository info and managed worktrees (default)
  ls|list                List Claude-related files in the current worktree.
                         Files tracked or visible to git are highlighted.
  ignore                 Add Claude-related patterns to .git/info/exclude
  unignore               Remove Claude-related patterns from .git/info/exclude
  save                   Save Claude-related files from the current worktree to
                         ~/.clc/saved/<repo>/<timestamp>/
  compare                Compare current worktree against the latest saved state.
                         Exits 0 if in sync, 1 if differences exist.
  restore                Restore Claude files from the latest saved state to the
                         current worktree. Prompts before making any changes.
  new|add [-c] <name> [<branch>]
                         Create a new managed peer worktree. Worktree name
                         derived from <name>: last path component, ticket
                         prefix stripped (e.g. feature/PROJ-123_foo → foo).
                         Branch defaults to <name> as-is; pass <branch> to
                         override. Checks out existing branch or creates new.
  rm|remove [-b] <name>  Remove a managed peer worktree. Fails if the worktree
                         is current or has uncommitted changes.
  prune|clean [-b]       Remove all managed peer worktrees that are not current
                         and have no uncommitted changes.

  -b, --with-branch  (rm, prune) Also delete the worktree's git branch with
                     'git branch -d'. Failure is reported as a warning.
  -c, --with-claude  (new) After creating the worktree, restore Claude files
                     from the latest saved state. Prompts only for destructive
                     operations (overwrite or delete).

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
    local -a cmd_args=()
    OPT_NO_COLOR=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    usage; exit 0 ;;
            -V|--version) echo "clc ${CLC_VERSION}"; exit 0 ;;
            --no-color)   OPT_NO_COLOR=1 ;;
            -*)           if [[ -n "${action}" ]]; then
                              cmd_args+=("$1")
                          else
                              echo "clc: unknown option: $1" >&2
                              echo "Try 'clc --help' for usage." >&2; exit 1
                          fi ;;
            *)            if [[ -z "${action}" ]]; then
                              action="$1"
                          else
                              cmd_args+=("$1")
                          fi ;;
        esac
        shift
    done

    need_cmd git
    setup_color

    case "${action}" in
        ""|status)    cmd_status ;;
        ls|list)      cmd_ls ;;
        ignore)       cmd_ignore ;;
        unignore)     cmd_unignore ;;
        save)         cmd_save ;;
        compare)      cmd_compare ;;
        restore)      cmd_restore ;;
        new|add)      cmd_new "${cmd_args[@]}" ;;
        rm|remove)    cmd_rm "${cmd_args[@]}" ;;
        prune|clean)  cmd_prune "${cmd_args[@]}" ;;
        *) echo "clc: unknown action: ${action}" >&2
           echo "Try 'clc --help' for usage." >&2; exit 1 ;;
    esac
}

main "$@"
