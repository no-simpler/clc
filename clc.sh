#!/usr/bin/env bash
# clc - Claude Cloak
# Use Claude Code across worktrees without leaving traces.

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────

CLC_VERSION="2.1.2"
# Explicit CLC_STORE env override (captured at startup). When set, it overrides
# the v2 data/store root (back-compat + test isolation); see clc_data_dir.
CLC_STORE_OVERRIDE="${CLC_STORE:-}"

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
short_path() { echo "~${1#${HOME}}"; }

# Join the remaining args with the first arg as separator.
_join() {
    local sep="$1"; shift
    [[ $# -eq 0 ]] && return
    local out="$1"; shift
    for x in "$@"; do out+="${sep}${x}"; done
    echo "${out}"
}

# Print a section header with optional subtitle on the same line.
print_header() {
    local heading="$1" subtitle="${2-}"
    if [[ -n "${subtitle}" ]]; then
        echo "${CLR_BOLD}${heading}${CLR_RESET} (${subtitle})"
    else
        echo "${CLR_BOLD}${heading}${CLR_RESET}"
    fi
}


# ── Config / XDG ──────────────────────────────────────────────────────────────

# v2 XDG-based locations. CLC_STORE (if set in env) overrides the data root.
clc_config_dir() { echo "${XDG_CONFIG_HOME:-${HOME}/.config}/clc"; }
clc_data_dir()   { echo "${CLC_STORE_OVERRIDE:-${XDG_DATA_HOME:-${HOME}/.local/share}/clc}"; }
clc_state_dir()  { echo "${XDG_STATE_HOME:-${HOME}/.local/state}/clc"; }

# Path to the v2 config file (git-config format).
clc_config_file() { echo "$(clc_config_dir)/config"; }

# Read a config value; empty (and success) when missing — safe under set -e.
config_get() { git config -f "$(clc_config_file)" "$@" 2>/dev/null || true; }

# Write a config value; creates the config dir on demand.
config_set() { mkdir -p "$(clc_config_dir)"; git config -f "$(clc_config_file)" "$@"; }

# List all config entries; empty when the file is absent.
config_list() { git config -f "$(clc_config_file)" --list 2>/dev/null || true; }


# ── v2 store ──────────────────────────────────────────────────────────────────
#
# The central store is a non-bare git repo whose working tree mirrors each
# enrolled project's second brain under a HOME-relative path (§4.1). It is the
# sole backing for save/restore/compare/diff/ls/new; the legacy ~/.clc/saved
# timestamp snapshots have been removed (a one-shot `clc migrate` enrolls any
# repos still recorded there into the store).

# Path to the central store git repo.
clc_store_dir() { echo "$(clc_data_dir)/store"; }

# Path to the registry/manifest inside the store (committed; §4.3).
registry_file() { echo "$(clc_store_dir)/.clc/registry"; }

# Initialize the store git repo if not already present (idempotent).
# Stamps a fixed clc identity + gpgsign=false into the store's OWN .git/config so
# every store commit is unsigned with a stable author/committer (no per-commit -c
# needed). Seeds the registry and makes the initial commit with real wall-clock
# dates (tests pin them via GIT_*_DATE env).
store_init() {
    local store; store="$(clc_store_dir)"
    [[ -d "${store}/.git" ]] && return 0

    git init -q "${store}"
    git -C "${store}" config user.name "clc"
    git -C "${store}" config user.email "clc@localhost"
    git -C "${store}" config commit.gpgsign false

    mkdir -p "${store}/.clc"
    printf '%s\n' \
        '# clc registry — enrolled projects. Fields: <HOME-relative path> TAB <origin-url> [TAB <meta>…]' \
        > "$(registry_file)"

    git -C "${store}" add -A
    git -C "${store}" commit -q -m "init store"
}

# Run a command holding a mandatory advisory lock on the store (§4.10).
# mkdir-based for macOS portability (no flock). 30s timeout; releases on failure.
with_store_lock() {
    local lockdir; lockdir="$(clc_state_dir)/locks/store"
    mkdir -p "$(dirname "${lockdir}")"
    local waited=0
    while ! mkdir "${lockdir}" 2>/dev/null; do
        sleep 0.1
        waited=$(( waited + 1 ))
        [[ ${waited} -ge 300 ]] && die "could not acquire store lock (another clc running?)"
    done
    local rc=0
    "$@" || rc=$?
    rmdir "${lockdir}" 2>/dev/null || true
    return ${rc}
}

# Emit registry data lines (skip header/blank). Parse with:
#   while IFS=$'\t' read -r path origin _; do …; done
registry_read() {
    grep -v '^#' "$(registry_file)" 2>/dev/null | grep -v '^[[:space:]]*$' || true
}

# Add or update a registry entry. Idempotent (identical line = no-op; same path
# with a new origin replaces the line). Sorted-on-write, atomic. Callers MUST
# hold with_store_lock and commit the mutation themselves (helper is pure).
registry_add() {
    local rel="$1" origin="$2"
    local reg; reg="$(registry_file)"
    mkdir -p "$(dirname "${reg}")"
    {
        printf '%s\n' \
            '# clc registry — enrolled projects. Fields: <HOME-relative path> TAB <origin-url> [TAB <meta>…]'
        {
            registry_read | while IFS=$'\t' read -r path origin_old rest; do
                [[ "${path}" == "${rel}" ]] && continue
                printf '%s\t%s' "${path}" "${origin_old}"
                [[ -n "${rest}" ]] && printf '\t%s' "${rest}"
                printf '\n'
            done
            printf '%s\t%s\n' "${rel}" "${origin}"
        } | sort
    } > "${reg}.tmp"
    mv "${reg}.tmp" "${reg}"
}

# Remove a registry entry by path (no-op if absent). Sorted-on-write, atomic.
# Callers MUST hold with_store_lock and commit the mutation themselves.
registry_remove() {
    local rel="$1"
    local reg; reg="$(registry_file)"
    mkdir -p "$(dirname "${reg}")"
    {
        printf '%s\n' \
            '# clc registry — enrolled projects. Fields: <HOME-relative path> TAB <origin-url> [TAB <meta>…]'
        registry_read | while IFS=$'\t' read -r path origin_old rest; do
            [[ "${path}" == "${rel}" ]] && continue
            printf '%s\t%s' "${path}" "${origin_old}"
            [[ -n "${rest}" ]] && printf '\t%s' "${rest}"
            printf '\n'
        done | sort
    } > "${reg}.tmp"
    mv "${reg}.tmp" "${reg}"
}

# Re-materialize a project's second brain into the store subtree and commit it
# (§4.2 executable spec, VERBATIM). Subtree-scoped + delete-aware. MUST be called
# under with_store_lock. rel = HOME-relative project path (store mirror subdir);
# wt = source worktree. Sets _STORE_SYNC_RESULT to "synced" or "noop".
_STORE_SYNC_RESULT=""   # "synced" | "noop"
store_sync_project() {
    local rel="$1" wt="$2"
    local store S Ftmp
    store="$(clc_store_dir)"
    S="${store}/${rel}"
    mkdir -p "${S}"

    Ftmp=$(mktemp)
    collect_claude_files_in_dir "${wt}" > "${Ftmp}"   # brain files, relative to wt

    # Nested git boundary subtrees (relative to wt) — submodules and linked
    # worktrees (e.g. .claude/worktrees/<name>) — are nested projects with their own
    # store subtree under "${rel}/<boundary>". The brain collection prunes them, so
    # they never appear in Ftmp — orphan-removal below must skip them too, or syncing
    # the parent would clobber a boundary's separately-synced brain.
    local subtmp; subtmp=$(mktemp)
    _nested_git_boundaries "${wt}" > "${subtmp}"

    # Drop orphans: tracked files under rel that are no longer in the brain
    # (excluding files that belong to a nested boundary subtree).
    while IFS= read -r -d '' t; do
        local t_rel="${t#${rel}/}" b in_boundary=0
        while IFS= read -r b; do
            [[ -n "${b}" ]] || continue
            if [[ "${t_rel}" == "${b}/"* ]]; then in_boundary=1; break; fi
        done < "${subtmp}"
        [[ ${in_boundary} -eq 1 ]] && continue
        if ! grep -qxF "${t_rel}" "${Ftmp}"; then
            git -C "${store}" rm -q -- "${t}" >/dev/null 2>&1 || true
        fi
    done < <(git -C "${store}" ls-files -z -- "${rel}")
    rm -f "${subtmp}"

    # Copy current brain files into the subtree and stage them. The brain set is
    # already filtered by collect_claude_files_in_dir to respect the project's
    # .gitignore + global excludes (clc's own info/exclude disregarded), so the
    # store never receives transitively-ignored files (vendor/…/CLAUDE.md) or
    # per-machine ones (.claude/settings.local.json).
    while IFS= read -r f; do
        [[ -n "${f}" ]] || continue
        mkdir -p "$(dirname "${S}/${f}")"
        cp "${wt}/${f}" "${S}/${f}"
        git -C "${store}" add -- "${S}/${f}"
    done < "${Ftmp}"
    rm -f "${Ftmp}"

    # Belt-and-suspenders, subtree-scoped ONLY. Tolerate a vanished subtree
    # (empty-brain case: the explicit git rm above already removed it) — git
    # would otherwise emit "fatal: pathspec … did not match any files" to stderr.
    git -C "${store}" add -A -- "${rel}" 2>/dev/null || true

    if git -C "${store}" diff --cached --quiet -- "${rel}"; then
        _STORE_SYNC_RESULT="noop"; return 0
    fi
    git -C "${store}" commit -q -m "sync: ${rel}"
    _STORE_SYNC_RESULT="synced"; return 0
}

# Batch engine for `clc save --all`: sync every enrolled repo's main worktree brain
# into the store in one pass. MUST be called under with_store_lock. Iterates the
# (sorted) registry — order is deterministic. A repo absent on this machine is
# reported "missing" and skipped (not an error). Populates result globals rather
# than printing, mirroring store_sync_project's _STORE_SYNC_RESULT contract:
#   _SYNC_ALL_ROWS    — TAB-separated "<rel>\t<status>" lines (status may be colored)
#   _SYNC_ALL_SYNCED  — 1 if any repo actually changed (→ caller triggers one backup)
#   _SYNC_ALL_ANY     — 1 if the registry had at least one entry
_SYNC_ALL_ROWS=()
_SYNC_ALL_SYNCED=0
_SYNC_ALL_ANY=0
store_sync_all() {
    _SYNC_ALL_ROWS=(); _SYNC_ALL_SYNCED=0; _SYNC_ALL_ANY=0
    local rel localpath
    while IFS=$'\t' read -r rel _ _; do
        [[ -n "${rel}" ]] || continue
        _SYNC_ALL_ANY=1
        localpath="${HOME}/${rel}"
        if dir_is_empty "${localpath}"; then
            _SYNC_ALL_ROWS+=("${rel}"$'\t'"${CLR_MUTED}missing${CLR_RESET}")
            continue
        fi
        store_sync_project "${rel}" "${localpath}"
        if [[ "${_STORE_SYNC_RESULT}" == "synced" ]]; then
            _SYNC_ALL_ROWS+=("${rel}"$'\t'"synced")
            _SYNC_ALL_SYNCED=1
        else
            _SYNC_ALL_ROWS+=("${rel}"$'\t'"${CLR_MUTED}up to date${CLR_RESET}")
        fi
    done < <(registry_read)
}


# ── v2 hooks ──────────────────────────────────────────────────────────────────
#
# Hooks are per-`.git` (shared across worktrees) so they install ONCE at the main
# gitdir. Each managed hook gets a sentinel-marked block appended without
# clobbering pre-existing user content; composes with husky/lefthook/core.hooksPath
# (§6.5). The block calls `clc sync --from-hook` fail-safe (never blocks the commit).

CLC_HOOK_BEGIN="# >>> clc managed >>>"
CLC_HOOK_END="# <<< clc managed <<<"
CLC_HOOKS="post-commit post-merge post-checkout"

# Resolve the absolute path of the running clc ONCE, baked into the hook line
# (robust in git's minimal-PATH hook environment; hooks are local/.git, never
# committed). Prefer a stable PATH entry (e.g. Homebrew's /opt/homebrew/bin/clc
# symlink) over realpath: realpath resolves into a version-pinned Cellar dir that
# `brew upgrade` deletes, which would silently break auto-sync. Fall back to this
# script's own absolute path (manual install / running ./clc.sh directly).
_CLC_SELF=""
clc_self() {
    if [[ -z "${_CLC_SELF}" ]]; then
        # Use the invocation path as-is, made absolute but WITHOUT resolving
        # symlinks. `realpath` would resolve a Homebrew bin symlink into a
        # version-pinned Cellar path that `brew upgrade` deletes, breaking baked
        # hooks. When invoked via PATH as `clc`, BASH_SOURCE is already the stable
        # symlink (e.g. /opt/homebrew/bin/clc); when run as ./clc.sh it's the file.
        local p="${BASH_SOURCE[0]:-$0}"
        [[ "${p}" == /* ]] || p="$(cd "$(dirname "${p}")" 2>/dev/null && pwd)/$(basename "${p}")"
        _CLC_SELF="${p}"
    fi
    echo "${_CLC_SELF}"
}

# Directory where hooks live for the given main gitdir. Honors core.hooksPath
# (composes with husky/lefthook); else <main_gitdir>/hooks (§6.5).
hooks_dir() {
    local main_gitdir="$1"
    local hp
    hp=$(git config -f "${main_gitdir}/config" core.hooksPath 2>/dev/null || true)
    if [[ -n "${hp}" ]]; then
        if [[ "${hp}" != /* ]]; then
            # Relative to the main worktree.
            hp="$(git_main_worktree "${main_gitdir}")/${hp}"
        fi
        echo "${hp}"
    else
        echo "${main_gitdir}/hooks"
    fi
}

# Install the managed block into each hook (idempotent, non-clobbering).
install_hooks() {
    local main_gitdir="$1"
    local dir self hook file
    dir=$(hooks_dir "${main_gitdir}")
    self=$(clc_self)
    mkdir -p "${dir}"
    for hook in ${CLC_HOOKS}; do
        file="${dir}/${hook}"
        if [[ -f "${file}" ]] && grep -qF "${CLC_HOOK_BEGIN}" "${file}" 2>/dev/null; then
            continue   # already managed — idempotent
        fi
        if [[ ! -f "${file}" ]]; then
            printf '%s\n' '#!/usr/bin/env bash' > "${file}"
        fi
        {
            printf '%s\n' "${CLC_HOOK_BEGIN}"
            printf '"%s" sync --from-hook >/dev/null || true\n' "${self}"
            printf '%s\n' "${CLC_HOOK_END}"
        } >> "${file}"
        chmod +x "${file}"
    done
}

# Remove the managed block from each hook by its sentinels. Delete the file only
# if nothing but a shebang and/or blank lines remains (covers the clc-created
# case; never deletes a file with real user content). Never touches files lacking
# the sentinel.
uninstall_hooks() {
    local main_gitdir="$1"
    local dir hook file
    dir=$(hooks_dir "${main_gitdir}")
    for hook in ${CLC_HOOKS}; do
        file="${dir}/${hook}"
        [[ -f "${file}" ]] || continue
        grep -qF "${CLC_HOOK_BEGIN}" "${file}" 2>/dev/null || continue
        awk -v b="${CLC_HOOK_BEGIN}" -v e="${CLC_HOOK_END}" '
            $0 == b { skip = 1; next }
            $0 == e { skip = 0; next }
            !skip   { print }
        ' "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
        # Delete if only a shebang and/or blank lines remain.
        if ! grep -qvE '^(#!.*|[[:space:]]*)$' "${file}" 2>/dev/null; then
            rm -f "${file}"
        fi
    done
}

# Return 0 if the named hook contains the clc sentinel in the given main gitdir.
hook_installed() {
    local main_gitdir="$1" hook="$2"
    local file; file="$(hooks_dir "${main_gitdir}")/${hook}"
    [[ -f "${file}" ]] && grep -qF "${CLC_HOOK_BEGIN}" "${file}" 2>/dev/null
}

# Return 0 if the project (identified by its main worktree) is enrolled: the store
# exists AND its registry lists the project by its HOME-relative path. Content-
# derived, never resurrects anything. Shared by cmd_status and the --from-hook gate.
is_enrolled() {
    local main_worktree="$1"
    local rel="${main_worktree#${HOME}/}"
    [[ "${rel}" != "${main_worktree}" ]] || return 1
    [[ -d "$(clc_store_dir)/.git" ]] || return 1
    local path _rest
    while IFS=$'\t' read -r path _rest; do
        [[ "${path}" == "${rel}" ]] && return 0
    done < <(registry_read)
    return 1
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
# For submodules the gitdir lives inside the parent's .git/modules/, so
# dirname would be wrong.  core.worktree in the gitdir config points back
# to the real working directory; regular repos don't set it, so dirname
# remains the fallback.
git_main_worktree() {
    local main_gitdir="$1"
    local worktree
    worktree=$(git config -f "${main_gitdir}/config" core.worktree 2>/dev/null)
    if [[ -n "${worktree}" ]]; then
        # core.worktree may be relative to the gitdir
        if [[ "${worktree}" != /* ]]; then
            worktree="${main_gitdir}/${worktree}"
        fi
        realpath "${worktree}"
    else
        dirname "${main_gitdir}"
    fi
}

# Absolute path of the current worktree root (the worktree $PWD belongs to).
git_current_worktree() {
    git rev-parse --show-toplevel 2>/dev/null
}

# ── Managed-worktree helpers ──────────────────────────────────────────────────

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
            printf '%s\n' "main"$'\002'"main"$'\002'"${wt_path}"$'\002'"${wt_branch}"$'\002'"${wt_dirty}"
        elif [[ "${wt_path}" == "${parent}/${base}-"* ]]; then
            local wt_name="${wt_path##*/${base}-}"
            printf '%s\n' "peer"$'\002'"${wt_name}"$'\002'"${wt_path}"$'\002'"${wt_branch}"$'\002'"${wt_dirty}"
        else
            printf '%s\n' "unmanaged"$'\002\002'"${wt_path}"$'\002'"${wt_branch}"$'\002'"${wt_dirty}"
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

# Print relative paths of the managed Claude files in a directory (sorted, unique).
#
# The brain definition (CLAUDE.md at any depth + a root .claude/) is collected via
# find, then files the project itself gitignores are dropped: clc respects the
# project's .gitignore files (any depth) and the user's global excludes, so
# transitively-ignored files (e.g. a dependency's vendor/…/CLAUDE.md) and
# per-machine ones (.claude/settings.local.json) stay out of the managed brain.
# clc's OWN .git/info/exclude patterns are deliberately disregarded — otherwise
# the brain, which clc locally-ignores on purpose, would never be stored.
collect_claude_files_in_dir() {
    local base="$1"
    local -a results=()

    # Prune nested git boundaries (.git internals + submodules / linked worktrees
    # such as Claude Code's .claude/worktrees/<name>, whose files belong to a
    # separate project) from the .claude/ walk; -prune keeps find from ever
    # descending into them, so a nested worktree's tens of thousands of files cost
    # nothing. The CLAUDE.md walk below prunes the same boundaries via
    # _find_claude_md_files.
    local -a prune=(-name ".git") b
    while IFS= read -r b; do
        [[ -n "${b}" ]] && prune+=(-o -path "${base}/${b}")
    done < <(_nested_git_boundaries "${base}")

    if [[ -d "${base}/.claude" ]]; then
        while IFS= read -r f; do results+=("${f#${base}/}"); done \
            < <(find "${base}/.claude" \( "${prune[@]}" \) -prune -o -type f -print 2>/dev/null | sort)
    fi
    while IFS= read -r f; do results+=("${f#${base}/}"); done \
        < <(_find_claude_md_files "${base}")
    [[ ${#results[@]} -eq 0 ]] && return

    local all ignored
    all=$(printf '%s\n' "${results[@]}" | sort -u)
    ignored=$(printf '%s\n' "${all}" | _brain_ignored_paths "${base}")
    if [[ -n "${ignored}" ]]; then
        comm -23 <(printf '%s\n' "${all}") <(printf '%s\n' "${ignored}" | sort -u)
    else
        printf '%s\n' "${all}"
    fi
}

# Echo, from relative paths read on stdin, the subset that the project at $1
# gitignores via its .gitignore files or the user's global excludes — DISREGARDING
# clc's own .git/info/exclude. Evaluated through a throwaway gitdir whose
# info/exclude is empty, layered over the same work tree, so only .gitignore and
# the global core.excludesfile apply (clc's /.claude/ blanket can't shadow a
# lower-precedence global rule such as **/.claude/settings.local.json this way).
_brain_ignored_paths() {
    local base="$1" gd
    gd=$(mktemp -d)
    git --git-dir="${gd}" init -q 2>/dev/null
    git --git-dir="${gd}" --work-tree="${base}" -C "${base}" \
        -c core.quotePath=false check-ignore --stdin 2>/dev/null || true
    rm -rf "${gd}"
}

# Print paths (relative to base) of nested git boundaries: a submodule or a linked
# worktree nested inside base (e.g. Claude Code's .claude/worktrees/<name>). Their
# contents belong to a separate project, never the outer brain, so callers prune them.
#
# Detected via git, not a filesystem walk: a brain that hosts a full nested worktree
# can have tens of thousands of files, and walking them on every call made
# `clc compare`/`ls` take ~30s. `git worktree list` + `submodule status` answer in
# milliseconds without descending into those trees. base is always a worktree
# toplevel (a realpath, matching the realpaths git records), so the prefix test is
# exact; a store-mirror subdir yields nothing — its enclosing repo's worktrees do
# not nest under it and it has no submodules. The one case this does NOT catch is an
# unregistered hand-placed clone — far rarer than the worktree/submodule cases, and
# still a strict superset of the prior submodule-only handling.
_nested_git_boundaries() {
    local base="$1"
    {
        # Linked worktrees registered for this repo, kept only when nested under base
        # and emitted base-relative. Filtering in awk (not a shell `while` loop)
        # keeps this clean under `set -euo pipefail`: a loop body of `[[…]] && printf`
        # returns non-zero whenever a worktree is NOT under base — including the main
        # worktree — which with pipefail would abort before the submodule check below.
        # `|| true` guards each read so a git error never trips the same trap.
        git -C "${base}" worktree list --porcelain 2>/dev/null \
            | awk -v b="${base}/" '/^worktree / { p = substr($0, 10); if (index(p, b) == 1) print substr(p, length(b) + 1) }' \
            || true
        # Submodules (status --recursive prints paths already relative to base).
        git -C "${base}" submodule status --recursive 2>/dev/null | awk '{print $2}' || true
    } | sort -u
}

# Find CLAUDE.md files in a directory, excluding .git internals and nested git
# boundaries (submodules, linked worktrees, nested clones). Uses -prune so find
# never descends into excluded dirs (faster, and keeps a sibling project's files
# out of this brain).
_find_claude_md_files() {
    local base="$1"
    local -a prune=(-name ".git")
    while IFS= read -r b_path; do
        [[ -n "${b_path}" ]] && prune+=(-o -path "${base}/${b_path}")
    done < <(_nested_git_boundaries "${base}")
    find "${base}" \( "${prune[@]}" \) -prune -o \
        -name "CLAUDE.md" -type f -print 2>/dev/null | sort
}

# Echo the store mirror dir ($store/$rel) for a repo's HEAD-committed brain.
# "storage" means the git store mirror subtree, keyed by the main worktree's
# HOME-relative path.
# Returns non-zero (no output) when: project not under $HOME, store absent, or
# the project has no tracked brain in the store ("no saved state" equivalent).
store_mirror_dir() {
    local main_worktree="$1"
    local rel="${main_worktree#${HOME}/}"
    [[ "${rel}" != "${main_worktree}" ]] || return 1
    local store; store="$(clc_store_dir)"
    [[ -d "${store}/.git" ]] || return 1
    git -C "${store}" ls-files -- "${rel}" 2>/dev/null | grep -q . || return 1
    echo "${store}/${rel}"
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

    local tmp_wt tmp_storage
    tmp_wt=$(mktemp) tmp_storage=$(mktemp)
    collect_claude_files_in_dir "${wt}"       > "$tmp_wt"
    collect_claude_files_in_dir "${save_dir}" > "$tmp_storage"

    # The worktree collection prunes nested git boundaries — submodules and linked
    # worktrees (e.g. .claude/worktrees/<name>) — which are separate projects with
    # their own store subtree. Prune the same paths from the storage side so a
    # parent's mirror — which physically nests those projects' synced files —
    # compares symmetrically. No-op for repos without nested boundaries and for a
    # boundary's own (un-nested) subtree.
    local b
    while IFS= read -r b; do
        [[ -n "${b}" ]] || continue
        grep -v "^${b}/" "$tmp_storage" > "${tmp_storage}.f" 2>/dev/null || true
        mv "${tmp_storage}.f" "$tmp_storage"
    done < <(_nested_git_boundaries "${wt}")

    while IFS= read -r f; do _CMP_ONLY_STORAGE+=("$f"); done  < <(comm -23 "$tmp_storage" "$tmp_wt")
    while IFS= read -r f; do _CMP_ONLY_WORKTREE+=("$f"); done < <(comm -13 "$tmp_storage" "$tmp_wt")
    while IFS= read -r f; do
        if cmp -s "${wt}/${f}" "${save_dir}/${f}"; then
            _CMP_SAME+=("$f")
        else
            _CMP_DIFFERENT+=("$f")
        fi
    done < <(comm -12 "$tmp_storage" "$tmp_wt")
    rm -f "$tmp_wt" "$tmp_storage"
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

# Print buffered "<rel>TAB<status>" rows as an aligned two-column list. Column width
# is derived from the (color-free) rel paths; status text may carry color codes.
# Used by the --all variants of save/compare for their per-repo summary.
_print_repo_rows() {
    local maxw=0 row rel
    for row in "$@"; do
        rel="${row%%$'\t'*}"
        [[ ${#rel} -gt ${maxw} ]] && maxw=${#rel}
    done
    for row in "$@"; do
        rel="${row%%$'\t'*}"
        printf "  %-*s  %s\n" "${maxw}" "${rel}" "${row#*$'\t'}"
    done
}

# ── Commands ──────────────────────────────────────────────────────────────────

# Audit every enrolled repo's brain against the store (clc compare --all). Read-only,
# no lock, runnable from anywhere. One line per repo: in sync / drifted (N) /
# never synced / missing. Returns 1 if any present repo has drifted, else 0.
cmd_compare_all() {
    local -a rows=()
    local any=0 drift_any=0 rel localpath save_dir diffs
    while IFS=$'\t' read -r rel _ _; do
        [[ -n "${rel}" ]] || continue
        any=1
        localpath="${HOME}/${rel}"
        if dir_is_empty "${localpath}"; then
            rows+=("${rel}"$'\t'"${CLR_MUTED}missing${CLR_RESET}")
            continue
        fi
        if ! save_dir=$(store_mirror_dir "${localpath}" 2>/dev/null); then
            rows+=("${rel}"$'\t'"${CLR_MUTED}never synced${CLR_RESET}")
            continue
        fi
        _compare_claude_files "${localpath}" "${save_dir}"
        diffs=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} ))
        if [[ ${diffs} -eq 0 ]]; then
            rows+=("${rel}"$'\t'"in sync")
        else
            rows+=("${rel}"$'\t'"${CLR_WARN}drifted (${diffs})${CLR_RESET}")
            drift_any=1
        fi
    done < <(registry_read)

    print_header "Compare (all enrolled)"
    if [[ ${any} -eq 0 ]]; then
        echo "  ${CLR_MUTED}(nothing enrolled)${CLR_RESET}"
        return 0
    fi
    _print_repo_rows "${rows[@]}"
    return $(( drift_any ))
}

# Full git diff across every enrolled repo (clc diff --all). Per drifted repo, print
# a header then the storage→worktree deltas; in-sync/missing/never-synced repos get a
# one-line status. Returns 1 if any present repo has drifted, else 0.
cmd_diff_all() {
    local any=0 drift_any=0 rel localpath save_dir diffs f
    local -a git_color=()
    [[ "${OPT_NO_COLOR}" -eq 1 ]] && git_color=("--no-color")
    print_header "Diff (all enrolled)"
    while IFS=$'\t' read -r rel _ _; do
        [[ -n "${rel}" ]] || continue
        any=1
        localpath="${HOME}/${rel}"
        if dir_is_empty "${localpath}"; then
            printf "  %s  %smissing%s\n" "${rel}" "${CLR_MUTED}" "${CLR_RESET}"
            continue
        fi
        if ! save_dir=$(store_mirror_dir "${localpath}" 2>/dev/null); then
            printf "  %s  %snever synced%s\n" "${rel}" "${CLR_MUTED}" "${CLR_RESET}"
            continue
        fi
        _compare_claude_files "${localpath}" "${save_dir}"
        diffs=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} ))
        if [[ ${diffs} -eq 0 ]]; then
            printf "  %s  %sin sync%s\n" "${rel}" "${CLR_MUTED}" "${CLR_RESET}"
            continue
        fi
        drift_any=1
        printf "\n%s%s%s\n" "${CLR_BOLD}" "${rel}" "${CLR_RESET}"
        for f in ${_CMP_ONLY_STORAGE[@]+"${_CMP_ONLY_STORAGE[@]}"}; do
            git diff --no-index ${git_color[@]+"${git_color[@]}"} -- "${save_dir}/${f}" /dev/null || true
        done
        for f in ${_CMP_DIFFERENT[@]+"${_CMP_DIFFERENT[@]}"}; do
            git diff --no-index ${git_color[@]+"${git_color[@]}"} -- "${save_dir}/${f}" "${localpath}/${f}" || true
        done
        for f in ${_CMP_ONLY_WORKTREE[@]+"${_CMP_ONLY_WORKTREE[@]}"}; do
            git diff --no-index ${git_color[@]+"${git_color[@]}"} -- /dev/null "${localpath}/${f}" || true
        done
    done < <(registry_read)

    if [[ ${any} -eq 0 ]]; then
        echo "  ${CLR_MUTED}(nothing enrolled)${CLR_RESET}"
        return 0
    fi
    return $(( drift_any ))
}

# Reconcile every enrolled repo's worktree from the store (clc restore --all). Per
# drifted repo, delegates to _apply_restore (which keeps its per-repo data-loss
# prompt); in-sync/missing/never-synced repos get a one-line status and are skipped.
cmd_restore_all() {
    local any=0 rel localpath save_dir diffs line
    print_header "Restore (all enrolled)"
    # Buffer the registry first: iterating via `while read < <(registry_read)` would
    # redirect the loop body's stdin to the process substitution, starving
    # _apply_restore's interactive [y/N] prompt. A plain for-loop keeps real stdin.
    local -a entries=()
    while IFS= read -r line; do entries+=("${line}"); done < <(registry_read)
    for line in ${entries[@]+"${entries[@]}"}; do
        rel="${line%%$'\t'*}"
        [[ -n "${rel}" ]] || continue
        any=1
        localpath="${HOME}/${rel}"
        if dir_is_empty "${localpath}"; then
            printf "  %s  %smissing%s\n" "${rel}" "${CLR_MUTED}" "${CLR_RESET}"
            continue
        fi
        if ! save_dir=$(store_mirror_dir "${localpath}" 2>/dev/null); then
            printf "  %s  %snever synced%s\n" "${rel}" "${CLR_MUTED}" "${CLR_RESET}"
            continue
        fi
        _compare_claude_files "${localpath}" "${save_dir}"
        diffs=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} ))
        if [[ ${diffs} -eq 0 ]]; then
            printf "  %s  %sin sync%s\n" "${rel}" "${CLR_MUTED}" "${CLR_RESET}"
            continue
        fi
        printf "\n%s%s%s\n" "${CLR_BOLD}" "${rel}" "${CLR_RESET}"
        _apply_restore "${localpath}" "${save_dir}" || true
    done

    [[ ${any} -eq 0 ]] && echo "  ${CLR_MUTED}(nothing enrolled)${CLR_RESET}"
    return 0
}

cmd_compare() {
    local opt_all=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all) opt_all=1 ;;
            -*) die "unknown option for 'compare': $1" ;;
            *)  die "unexpected argument: $1" ;;
        esac
        shift
    done
    [[ ${opt_all} -eq 1 ]] && { cmd_compare_all; return; }

    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)       || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                         || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                         || die "unable to determine current worktree"

    local save_dir
    save_dir=$(store_mirror_dir "${main_worktree}") \
        || die "no saved state found — run 'clc save' first"

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

cmd_diff() {
    local opt_all=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all) opt_all=1 ;;
            -*) die "unknown option for 'diff': $1" ;;
            *)  die "unexpected argument: $1" ;;
        esac
        shift
    done
    [[ ${opt_all} -eq 1 ]] && { cmd_diff_all; return; }

    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)       || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                         || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                         || die "unable to determine current worktree"

    local save_dir
    save_dir=$(store_mirror_dir "${main_worktree}") \
        || die "no saved state found — run 'clc save' first"

    _compare_claude_files "${current_worktree}" "${save_dir}"
    local total=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} + ${#_CMP_SAME[@]} ))
    local diffs=$(( ${#_CMP_ONLY_STORAGE[@]} + ${#_CMP_DIFFERENT[@]} + ${#_CMP_ONLY_WORKTREE[@]} ))

    if [[ ${diffs} -eq 0 ]]; then
        echo "All ${total} Claude file(s) in current worktree are in sync with storage."
        return 0
    fi

    local -a git_color=()
    [[ "${OPT_NO_COLOR}" -eq 1 ]] && git_color=("--no-color")

    # Only in storage: file was deleted from worktree — show as deletion
    for f in ${_CMP_ONLY_STORAGE[@]+"${_CMP_ONLY_STORAGE[@]}"}; do
        git diff --no-index ${git_color[@]+"${git_color[@]}"} -- "${save_dir}/${f}" /dev/null || true
    done
    # Different content: show storage → worktree delta
    for f in ${_CMP_DIFFERENT[@]+"${_CMP_DIFFERENT[@]}"}; do
        git diff --no-index ${git_color[@]+"${git_color[@]}"} -- "${save_dir}/${f}" "${current_worktree}/${f}" || true
    done
    # Only in worktree: new file not yet saved — show as addition
    for f in ${_CMP_ONLY_WORKTREE[@]+"${_CMP_ONLY_WORKTREE[@]}"}; do
        git diff --no-index ${git_color[@]+"${git_color[@]}"} -- /dev/null "${current_worktree}/${f}" || true
    done

    return 1
}

cmd_restore() {
    local opt_all=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all) opt_all=1 ;;
            -*) die "unknown option for 'restore': $1" ;;
            *)  die "unexpected argument: $1" ;;
        esac
        shift
    done
    [[ ${opt_all} -eq 1 ]] && { cmd_restore_all; return; }

    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)       || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                         || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                         || die "unable to determine current worktree"

    local save_dir
    save_dir=$(store_mirror_dir "${main_worktree}") \
        || die "no saved state found — run 'clc save' first"

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
    local opt_no_claude=0 full_name="" branch=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--no-claude) opt_no_claude=1 ;;
            -*) die "unknown option for 'new': $1" ;;
            *)  if   [[ -z "${full_name}" ]]; then full_name="$1"
                elif [[ -z "${branch}"    ]]; then branch="$1"
                else die "unexpected argument: $1"
                fi ;;
        esac
        shift
    done
    [[ -n "${full_name}" ]] || die "usage: clc new [-n|--no-claude] <name> [<branch>]"

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

    if [[ ${opt_no_claude} -eq 0 ]]; then
        local save_dir
        if save_dir=$(store_mirror_dir "${main_worktree}"); then
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
    local opt_keep_branch=0 name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -k|--keep-branch) opt_keep_branch=1 ;;
            -*) die "unknown option for 'rm': $1" ;;
            *)  if [[ -z "${name}" ]]; then name="$1"
                else die "unexpected argument: $1"
                fi ;;
        esac
        shift
    done
    [[ -n "${name}" ]] || die "usage: clc rm [-k|--keep-branch] <name>"

    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)    || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") \
                                      || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) \
                                      || die "unable to determine current worktree"

    # Find the peer by name.
    local wt_path="" wt_branch="" wt_dirty=""
    while IFS=$'\002' read -r type row_name path branch dirty; do
        if [[ "${type}" == "peer" && "${row_name}" == "${name}" ]]; then
            wt_path="${path}"; wt_branch="${branch}"; wt_dirty="${dirty}"
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
    if [[ ${opt_keep_branch} -eq 0 ]]; then
        local branch_sha
        branch_sha=$(git -C "${main_worktree}" rev-parse "${wt_branch}" 2>/dev/null || true)
        if git -C "${main_worktree}" branch -d "${wt_branch}" >/dev/null 2>&1; then
            printf "      %sbranch deleted%s\n" "${CLR_MUTED}" "${CLR_RESET}"
            printf "      %sgit branch %s %s%s\n" "${CLR_MUTED}" "${wt_branch}" "${branch_sha}" "${CLR_RESET}"
        else
            print_warning_line "branch '${wt_branch}' not deleted — not fully merged"
        fi
    fi
    echo

    cmd_status
}

cmd_prune() {
    local opt_keep_branch=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -k|--keep-branch) opt_keep_branch=1 ;;
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
    while IFS=$'\002' read -r type name path branch dirty; do
        [[ "${type}" == "peer" ]]                || continue
        [[ "${path}" != "${current_worktree}" ]] || continue
        [[ -z "${dirty}" ]]                      || continue
        to_remove+=("${name}"$'\002'"${path}"$'\002'"${branch}")
    done < <(list_all_worktrees "${main_worktree}")

    print_header "Pruned"
    if [[ ${#to_remove[@]} -eq 0 ]]; then
        echo "  ${CLR_MUTED}(nothing to prune)${CLR_RESET}"
    else
        for row in "${to_remove[@]}"; do
            local r_name r_path r_branch
            IFS=$'\002' read -r r_name r_path r_branch <<< "${row}"
            local r_sha
            r_sha=$(git -C "${main_worktree}" rev-parse "${r_branch}" 2>/dev/null || true)
            git -C "${main_worktree}" worktree remove "${r_path}" >/dev/null 2>&1 \
                || die "failed to remove worktree '${r_name}'"
            [[ -d "${r_path}" ]] && rm -rf "${r_path}"
            echo "  - ${r_name}  ${CLR_MUTED}(${r_branch})${CLR_RESET}"
            if [[ ${opt_keep_branch} -eq 0 ]]; then
                if git -C "${main_worktree}" branch -d "${r_branch}" >/dev/null 2>&1; then
                    printf "      %sbranch deleted%s\n" "${CLR_MUTED}" "${CLR_RESET}"
                    printf "      %sgit branch %s %s%s\n" "${CLR_MUTED}" "${r_branch}" "${r_sha}" "${CLR_RESET}"
                else
                    print_warning_line "branch '${r_branch}' not deleted — not fully merged"
                fi
            fi
        done
    fi
    echo

    cmd_status
}

# Append the two CLC patterns to .git/info/exclude (skip those already present).
# Echoes each pattern it added (one per line) so callers can report. Pure helper
# shared by cmd_ignore and cmd_enroll.
_ignore_patterns() {
    local main_gitdir="$1"
    local exclude_file="${main_gitdir}/info/exclude"
    mkdir -p "${main_gitdir}/info"
    [[ -f "${exclude_file}" ]] || touch "${exclude_file}"
    for pat in "${CLC_PAT_MD}" "${CLC_PAT_DIR}"; do
        if ! grep -qxF "${pat}" "${exclude_file}" 2>/dev/null; then
            echo "${pat}" >> "${exclude_file}"
            echo "${pat}"
        fi
    done
}

# Remove the two CLC patterns from .git/info/exclude if present. Echoes each
# pattern it removed (one per line). Pure helper shared by cmd_unignore/cmd_unenroll.
_unignore_patterns() {
    local main_gitdir="$1"
    local exclude_file="${main_gitdir}/info/exclude"
    [[ -f "${exclude_file}" ]] || return 0
    for pat in "${CLC_PAT_MD}" "${CLC_PAT_DIR}"; do
        if grep -qxF "${pat}" "${exclude_file}" 2>/dev/null; then
            grep -vxF "${pat}" "${exclude_file}" > "${exclude_file}.tmp" || true
            mv "${exclude_file}.tmp" "${exclude_file}"
            echo "${pat}"
        fi
    done
}

cmd_ignore() {
    local main_gitdir
    main_gitdir=$(git_main_gitdir) || die "not inside a Git repository"

    local -a added=()
    while IFS= read -r pat; do
        [[ -n "${pat}" ]] && added+=("${pat}")
    done < <(_ignore_patterns "${main_gitdir}")

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
    local main_gitdir
    main_gitdir=$(git_main_gitdir) || die "not inside a Git repository"

    local -a removed=()
    while IFS= read -r pat; do
        [[ -n "${pat}" ]] && removed+=("${pat}")
    done < <(_unignore_patterns "${main_gitdir}")

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
    done < <(_find_claude_md_files "${current_worktree}")

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

    # Storage comparison (against the git store mirror).
    local save_dir; save_dir=$(store_mirror_dir "${main_worktree}" || true)
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

    # ── Enrollment state (content-derived; absent entirely when not enrolled) ──
    # A repo is enrolled iff the store exists AND its registry lists this project
    # by its HOME-relative path. Everything is guarded so an unenrolled repo (no
    # store) renders NOTHING new, keeping pre-v2 snapshots byte-identical.
    local enrolled=0
    is_enrolled "${main_worktree}" && enrolled=1

    # ── Claude-file state for current worktree ────────────────────────────────
    local state_tracked=0 state_ignore state_gitignore=0
    claude_files_tracked   "${current_worktree}"     && state_tracked=1
    state_ignore=$(claude_local_ignore_state "${main_gitdir}")
    claude_in_gitignore    "${current_worktree}"     && state_gitignore=1

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
    while IFS=$'\002' read -r type name path branch dirty; do
        case "${type}" in
            main)     main_branch="${branch}"; main_dirty="${dirty}" ;;
            peer)     peer_rows+=("${name}"$'\002'"${path}"$'\002'"${branch}"$'\002'"${dirty}")
                      [[ ${#name} -gt ${max_peer_name_len} ]] && max_peer_name_len=${#name} ;;
            unmanaged) unmanaged_rows+=("${path}"$'\002'"${branch}"$'\002'"${dirty}") ;;
        esac
    done < <(list_all_worktrees "${main_worktree}")

    # Parent dir is shared by all managed worktrees; printed once in section 1.
    local parent_dir_abs parent_dir_disp
    parent_dir_abs=$(dirname "${main_worktree}")
    parent_dir_disp=$(short_path "${parent_dir_abs}")

    # Compute max visible content width across all sections for branch alignment.
    # Use basename for main worktree and short names for peers (already names).
    local main_name; main_name=$(basename "${main_worktree}")
    local max_content_len=${#main_name}
    [[ ${max_peer_name_len} -gt ${max_content_len} ]] && max_content_len=${max_peer_name_len}
    for row in ${unmanaged_rows[@]+"${unmanaged_rows[@]}"}; do
        local u_path u_branch u_display
        IFS=$'\002' read -r u_path u_branch <<< "${row}"
        if [[ "${u_path}" == "${parent_dir_abs}/"* ]]; then
            u_display="${u_path##${parent_dir_abs}/}"
        else
            u_display=$(short_path "${u_path}")
        fi
        [[ ${#u_display} -gt ${max_content_len} ]] && max_content_len=${#u_display}
    done

    # Section 1: Repository & main worktree
    print_header "Repository" "parent dir: ${parent_dir_disp}"
    local main_pad
    main_pad=$(( max_content_len - ${#main_name} ))
    local main_dirty_suffix=""
    [[ -n "${main_dirty}" ]] && main_dirty_suffix=" ${CLR_MUTED}(dirty)${CLR_RESET}"
    if [[ "${main_worktree}" == "${current_worktree}" ]]; then
        printf "  ${CLR_BOLD}*${CLR_RESET} ${CLR_BOLD}%-*s${CLR_RESET}  ${CLR_MUTED}(%s)${CLR_RESET}%s\n" \
            "${max_content_len}" "${main_name}" "${main_branch}" "${main_dirty_suffix}"
        # Combine main-level and current-level warnings (same line is both).
        local -a combined_warnings=()
        [[ ${#main_warnings[@]} -gt 0 ]] && combined_warnings+=("${main_warnings[@]}")
        [[ ${#cur_warnings[@]}  -gt 0 ]] && combined_warnings+=("${cur_warnings[@]}")
        if [[ ${#combined_warnings[@]} -gt 0 ]]; then print_warning_line "${combined_warnings[@]}"; fi
    else
        printf "    %-*s  ${CLR_MUTED}(%s)${CLR_RESET}%s\n" \
            "${max_content_len}" "${main_name}" "${main_branch}" "${main_dirty_suffix}"
        if [[ ${#main_warnings[@]} -gt 0 ]]; then print_warning_line "${main_warnings[@]}"; fi
    fi

    # Section 1.5: Enrollment (only when enrolled — absent otherwise so unenrolled
    # snapshots stay byte-identical).
    if [[ ${enrolled} -eq 1 ]]; then
        echo
        print_header "Enrollment"
        echo "  enrolled"
        local -a hooks_present=() hooks_missing=()
        local h
        for h in ${CLC_HOOKS}; do
            if hook_installed "${main_gitdir}" "${h}"; then
                hooks_present+=("${h}")
            else
                hooks_missing+=("${h}")
            fi
        done
        if [[ ${#hooks_missing[@]} -eq 0 ]]; then
            printf "  hooks: %s\n" "$(_join ', ' "${hooks_present[@]}")"
        elif [[ ${#hooks_present[@]} -eq 0 ]]; then
            printf "  hooks: %s(none installed)%s\n" "${CLR_MUTED}" "${CLR_RESET}"
        else
            printf "  hooks: %s %s(missing: %s)%s\n" \
                "$(_join ', ' "${hooks_present[@]}")" "${CLR_MUTED}" \
                "$(_join ', ' "${hooks_missing[@]}")" "${CLR_RESET}"
        fi
    fi

    # Section 1.6: Backups staleness (only when targets are configured — absent
    # otherwise so unconfigured snapshots stay byte-identical). The age is the lone
    # wall-clock line in routine output (§6.3); pinned in tests via CLC_NOW.
    local _bt; _bt="$(backup_targets)"
    if [[ -n "${_bt}" ]]; then
        echo
        print_header "Backups"
        local bname bkind
        while IFS= read -r bname; do
            [[ -n "${bname}" ]] || continue
            bkind=$(backup_get "${bname}" kind)
            printf "  %s %s(%s)%s  %s%s%s\n" \
                "${bname}" "${CLR_MUTED}" "${bkind}" "${CLR_RESET}" \
                "${CLR_MUTED}" "$(backup_age "${bname}")" "${CLR_RESET}"
        done <<< "${_bt}"
    fi

    # Section 2: Managed worktrees
    echo
    print_header "Managed worktrees"
    if [[ ${#peer_rows[@]} -eq 0 ]]; then
        echo "  ${CLR_MUTED}<none>${CLR_RESET}"
    else
        for row in "${peer_rows[@]}"; do
            local name path branch dirty dirty_suffix
            IFS=$'\002' read -r name path branch dirty <<< "${row}"
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
            local path branch dirty dirty_suffix u_disp
            IFS=$'\002' read -r path branch dirty <<< "${row}"
            dirty_suffix=""
            [[ -n "${dirty}" ]] && dirty_suffix=" ${CLR_MUTED}(dirty)${CLR_RESET}"
            if [[ "${path}" == "${parent_dir_abs}/"* ]]; then
                u_disp="${path##${parent_dir_abs}/}"
            else
                u_disp=$(short_path "${path}")
            fi
            if [[ "${path}" == "${current_worktree}" ]]; then
                printf "  ${CLR_BOLD}*${CLR_RESET} %-*s  ${CLR_MUTED}(%s)${CLR_RESET}%s\n" \
                    "${max_content_len}" "${u_disp}" "${branch}" "${dirty_suffix}"
                if [[ ${#cur_warnings[@]} -gt 0 ]]; then print_warning_line "${cur_warnings[@]}"; fi
            else
                printf "    %-*s  ${CLR_MUTED}(%s)${CLR_RESET}%s\n" \
                    "${max_content_len}" "${u_disp}" "${branch}" "${dirty_suffix}"
            fi
        done
    fi
}

# ── Transplant ────────────────────────────────────────────────────────────────

# Internal helper for pull/close. Performs sanity checks, optional rebase, and
# merge --squash.  Sets _PULL_WT_PATH, _PULL_WT_BRANCH, _PULL_FILE_COUNT for
# the caller.  Does NOT commit or remove.
_do_pull() {
    local cmd="$1" name="$2"

    # ── resolve context ──────────────────────────────────────────────────
    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)                              || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}")         || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree)                    || die "unable to determine current worktree"

    # ── sanity checks (all read-only, no mutations) ──────────────────────
    # 1. Must be in main worktree.
    [[ "${current_worktree}" == "${main_worktree}" ]] \
        || die "must be run from the main worktree (currently in '$(short_path "${current_worktree}")')"

    # 2. Find peer by name.
    local wt_path="" wt_branch="" wt_dirty=""
    while IFS=$'\002' read -r type row_name path branch dirty; do
        if [[ "${type}" == "peer" && "${row_name}" == "${name}" ]]; then
            wt_path="${path}"; wt_branch="${branch}"; wt_dirty="${dirty}"
        fi
    done < <(list_all_worktrees "${main_worktree}")
    [[ -n "${wt_path}" ]]   || die "no managed peer worktree named '${name}'"

    # 3. Main worktree is clean.
    [[ -z "$(git -C "${main_worktree}" status --porcelain)" ]] \
        || die "main worktree has uncommitted changes — commit or stash first"

    # 4. Peer worktree is clean.
    [[ -z "${wt_dirty}" ]]  || die "worktree '${name}' has uncommitted changes — commit first"

    # 5. Peer is not on a detached HEAD.
    [[ -n "${wt_branch}" && "${wt_branch}" != "(detached)" ]] \
        || die "peer '${name}' is on a detached HEAD"

    # 6. Resolve branches and verify relationship.
    local primary_branch primary_tip peer_tip merge_base
    primary_branch=$(git -C "${main_worktree}" symbolic-ref --short HEAD)
    primary_tip=$(git -C "${main_worktree}" rev-parse HEAD)
    peer_tip=$(git -C "${main_worktree}" rev-parse "${wt_branch}")

    merge_base=$(git -C "${main_worktree}" merge-base "${primary_tip}" "${wt_branch}" 2>/dev/null) \
        || die "branches '${primary_branch}' and '${wt_branch}' share no common history"

    # 7. Something to transplant.
    [[ "${primary_tip}" != "${peer_tip}" ]] \
        || die "nothing to transplant — '${wt_branch}' is identical to '${primary_branch}'"

    # ── step 1: rebase peer if needed ────────────────────────────────────
    local did_rebase=0
    if [[ "${merge_base}" != "${primary_tip}" ]]; then
        print_header "Rebasing"
        printf "  %s onto %s\n\n" "${wt_branch}" "${primary_branch}"
        local rebase_out
        if rebase_out=$(git ${GIT_SIGN[@]+"${GIT_SIGN[@]}"} -C "${wt_path}" rebase "${primary_branch}" 2>&1); then
            : # success — output suppressed
        else
            git -C "${wt_path}" rebase --abort 2>/dev/null || true
            printf "%s\n\n" "${rebase_out}"
            die "rebase failed due to conflicts — both worktrees are clean.
To proceed manually:

  cd $(short_path "${wt_path}") && git rebase ${primary_branch}
  # resolve conflicts, then: git rebase --continue

  cd $(short_path "${main_worktree}") && clc ${cmd} ${name}"
        fi
        did_rebase=1
    fi

    # ── step 2: transplant via merge --squash ────────────────────────────
    git -C "${main_worktree}" merge --squash "${wt_branch}" >/dev/null 2>&1 \
        || die "merge --squash failed unexpectedly"

    local file_count
    file_count=$(git -C "${main_worktree}" diff --cached --name-only | wc -l | tr -d ' ')

    print_header "Pulled"
    printf "  %s → %s\n" "${wt_branch}" "${primary_branch}"
    if [[ ${did_rebase} -eq 1 ]]; then
        printf "  %sRebased onto %s%s\n" "${CLR_MUTED}" "${primary_branch}" "${CLR_RESET}"
    fi
    printf "  %s file(s) staged\n" "${file_count}"

    # Export state for callers.
    _PULL_WT_PATH="${wt_path}"
    _PULL_WT_BRANCH="${wt_branch}"
    _PULL_FILE_COUNT="${file_count}"
}

cmd_pull() {
    local opt_commit=0 name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--commit) opt_commit=1 ;;
            -*) die "unknown option for 'pull': $1" ;;
            *)  if [[ -z "${name}" ]]; then name="$1"
                else die "unexpected argument: $1"
                fi ;;
        esac
        shift
    done
    [[ -n "${name}" ]] || die "usage: clc pull [-c|--commit] <name>"

    _do_pull "pull" "${name}"

    if [[ ${opt_commit} -eq 1 ]]; then
        echo
        if ! git ${GIT_SIGN[@]+"${GIT_SIGN[@]}"} commit; then
            echo
            die "commit aborted — changes remain staged"
        fi
    else
        echo
        echo "Changes are staged. Review with 'git diff --cached', then commit when ready."
    fi
}

cmd_close() {
    local opt_commit=0 opt_keep_branch=0 name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--commit)     opt_commit=1 ;;
            -k|--keep-branch) opt_keep_branch=1 ;;
            -*) die "unknown option for 'close': $1" ;;
            *)  if [[ -z "${name}" ]]; then name="$1"
                else die "unexpected argument: $1"
                fi ;;
        esac
        shift
    done
    [[ -n "${name}" ]] || die "usage: clc close [-c|--commit] [-k|--keep-branch] <name>"

    _do_pull "close" "${name}"

    if [[ ${opt_commit} -eq 1 ]]; then
        echo
        if ! git ${GIT_SIGN[@]+"${GIT_SIGN[@]}"} commit; then
            echo
            die "commit aborted — worktree '${name}' not removed"
        fi
    fi

    # Remove worktree (same pattern as cmd_rm).
    local main_gitdir main_worktree
    main_gitdir=$(git_main_gitdir)
    main_worktree=$(git_main_worktree "${main_gitdir}")

    git -C "${main_worktree}" worktree remove "${_PULL_WT_PATH}" >/dev/null 2>&1 \
        || die "failed to remove worktree '${name}'"
    [[ -d "${_PULL_WT_PATH}" ]] && rm -rf "${_PULL_WT_PATH}"

    echo
    print_header "Removed"
    printf "  %s  %s(%s)%s\n" "$(short_path "${_PULL_WT_PATH}")" "${CLR_MUTED}" "${_PULL_WT_BRANCH}" "${CLR_RESET}"
    if [[ ${opt_keep_branch} -eq 0 ]]; then
        local branch_sha
        branch_sha=$(git -C "${main_worktree}" rev-parse "${_PULL_WT_BRANCH}" 2>/dev/null || true)
        if git -C "${main_worktree}" branch -D "${_PULL_WT_BRANCH}" >/dev/null 2>&1; then
            printf "      %sbranch deleted%s\n" "${CLR_MUTED}" "${CLR_RESET}"
            printf "      %sgit branch %s %s%s\n" "${CLR_MUTED}" "${_PULL_WT_BRANCH}" "${branch_sha}" "${CLR_RESET}"
        else
            print_warning_line "branch '${_PULL_WT_BRANCH}' not deleted"
        fi
    fi

    if [[ ${opt_commit} -eq 0 ]]; then
        echo
        echo "Changes are staged. Review with 'git diff --cached', then commit when ready."
    fi
}

# ── v2 enrollment ─────────────────────────────────────────────────────────────

# Under-lock helper: register the project + commit the registry mutation, then
# do the initial brain sync (its own commit, or noop). Two distinct commits, both
# under one lock acquisition (§4.7).
_store_enroll() {
    local rel="$1" origin="$2" wt="$3"
    local store; store="$(clc_store_dir)"
    registry_add "${rel}" "${origin}"
    git -C "${store}" add -- .clc/registry
    git -C "${store}" diff --cached --quiet || git -C "${store}" commit -q -m "enroll: ${rel}"
    store_sync_project "${rel}" "${wt}"
}

# Under-lock helper: drop the registry entry + commit, then remove the project's
# store subtree + commit (each only if it actually changed anything).
_store_unenroll() {
    local rel="$1"
    local store; store="$(clc_store_dir)"
    registry_remove "${rel}"
    git -C "${store}" add -- .clc/registry
    git -C "${store}" diff --cached --quiet || git -C "${store}" commit -q -m "unenroll: ${rel}"
    if git -C "${store}" ls-files -- "${rel}" | grep -q .; then
        git -C "${store}" rm -r -q -- "${rel}" >/dev/null 2>&1 || true
        git -C "${store}" diff --cached --quiet || git -C "${store}" commit -q -m "unenroll: ${rel}"
    fi
}

# Enroll core (§4.7), decoupled from $PWD: gitignore + register + hooks + sync for
# a repo whose paths are already resolved. Shared by cmd_enroll (PWD-resolved) and
# cmd_migrate (per-candidate). Sets _STORE_SYNC_RESULT (read by callers for output).
# Args: <main_gitdir> <main_worktree> <current_worktree> [<rel>]. Returns non-zero
# (no side effects) when the repo is outside $HOME — caller decides how to report.
_enroll_at() {
    local main_gitdir="$1" main_worktree="$2" current_worktree="$3" rel="${4-}"

    # Identity = main worktree's HOME-relative path. Refuse, never guess, if outside $HOME.
    [[ -n "${rel}" ]] || rel="${main_worktree#${HOME}/}"
    [[ "${rel}" != "${main_worktree}" ]] || return 1
    local origin
    origin=$(git -C "${main_worktree}" config --get remote.origin.url 2>/dev/null || true)

    # 1. Local-gitignore the second brain.
    _ignore_patterns "${main_gitdir}" >/dev/null

    # 2+4. Register + initial sync (one lock acquisition, two store commits).
    store_init
    with_store_lock _store_enroll "${rel}" "${origin}" "${current_worktree}"

    # 3. Install hooks (once, at the main gitdir).
    install_hooks "${main_gitdir}"
}

# Graduate ignore → full enrollment (§4.7): gitignore + register + hooks + sync.
cmd_enroll() {
    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)       || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) || die "unable to determine current worktree"

    local rel="${main_worktree#${HOME}/}"
    [[ "${rel}" != "${main_worktree}" ]] || die "project is not under \$HOME — cannot derive store identity"

    _enroll_at "${main_gitdir}" "${main_worktree}" "${current_worktree}" "${rel}"

    print_header "Enrolled"
    echo "  registered"
    echo "  hooks: $(_join ', ' post-commit post-merge post-checkout)"
    if [[ "${_STORE_SYNC_RESULT}" == "noop" ]]; then
        echo "  brain: ${CLR_MUTED}(store already up to date)${CLR_RESET}"
    else
        local n; n=$(collect_claude_files_in_dir "${current_worktree}" | grep -c . || true)
        echo "  brain: ${n} Claude file(s) → store"
    fi
    echo

    cmd_status
}

# Reverse all four enrollment steps (§4.7).
cmd_unenroll() {
    local main_gitdir main_worktree current_worktree
    main_gitdir=$(git_main_gitdir)       || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) || die "unable to determine current worktree"

    local rel="${main_worktree#${HOME}/}"
    [[ "${rel}" != "${main_worktree}" ]] || die "project is not under \$HOME — cannot derive store identity"

    # 1. Deregister + drop store subtree (if the store exists at all).
    if [[ -d "$(clc_store_dir)/.git" ]]; then
        with_store_lock _store_unenroll "${rel}"
    fi

    # 2. Remove hooks.
    uninstall_hooks "${main_gitdir}"

    # 3. Un-ignore the second brain.
    _unignore_patterns "${main_gitdir}" >/dev/null

    print_header "Unenrolled"
    echo "  deregistered"
    echo "  hooks removed"
    echo "  brain dropped from store"
    echo

    cmd_status
}

# ── v2 migrate ────────────────────────────────────────────────────────────────
#
# One-shot v1→v2 helper (§7). v1 stored brains under "${root}/saved/<name>@<md5>/"
# with a sibling full-path.txt recording each repo's absolute path. Migrate uses
# those full-path.txt files as the enumeration source, verifies each candidate is
# genuinely clc-touched via the local-gitignore signal (the primary truth), and
# enrolls it into the v2 store. Pre-migration timestamp history is NOT replayed:
# enrollment performs a single "current brain" commit (§7.3). Idempotent.

# Legacy v1 saved-store dir. Honors the CLC_STORE override (tests + back-compat);
# the v2 store lives at "${root}/store" under the same override root, so legacy
# "saved/" and the new "store/" coexist without collision.
legacy_saved_dir() { echo "${CLC_STORE_OVERRIDE:-${HOME}/.clc}/saved"; }

cmd_migrate() {
    print_header "Migrate"

    local saved; saved="$(legacy_saved_dir)"
    if [[ ! -d "${saved}" ]]; then
        echo "  ${CLR_MUTED}(no legacy clc storage found)${CLR_RESET}"
        return 0
    fi

    local seen=" "   # space-delimited list of rels already handled (dedup)
    local found=0
    local fp abs main_gitdir main_worktree rel
    for fp in "${saved}"/*/full-path.txt; do
        [[ -f "${fp}" ]] || continue          # no-glob → literal pattern, skip
        found=1
        IFS= read -r abs < "${fp}" || true     # first line = repo abs path
        [[ -n "${abs}" ]] || continue

        # Candidate must still exist and be a git repo.
        [[ -d "${abs}" ]] || continue
        main_gitdir=$(cd "${abs}" 2>/dev/null && git_main_gitdir 2>/dev/null) || continue
        main_worktree=$(git_main_worktree "${main_gitdir}" 2>/dev/null) || continue

        # Verify via the local-gitignore signal (primary truth): "no" → not clc-touched.
        [[ "$(claude_local_ignore_state "${main_gitdir}")" != "no" ]] || continue

        # Identity = main worktree's HOME-relative path; skip + warn if outside $HOME.
        rel="${main_worktree#${HOME}/}"
        if [[ "${rel}" == "${main_worktree}" ]]; then
            echo "  $(short_path "${main_worktree}")"
            print_warning_line "not under \$HOME — cannot derive store identity; skipped"
            continue
        fi

        # Deduplicate: a repo may have several legacy <name>@<md5> dirs.
        case "${seen}" in *" ${rel} "*) continue ;; esac
        seen="${seen}${rel} "

        if is_enrolled "${main_worktree}"; then
            echo "  ${rel}  ${CLR_MUTED}already enrolled${CLR_RESET}"
            continue
        fi

        # Enroll it (one-time current-brain commit; pre-migration history dropped).
        _enroll_at "${main_gitdir}" "${main_worktree}" "${main_worktree}" "${rel}"
        local n; n=$(collect_claude_files_in_dir "${main_worktree}" | grep -c . || true)
        echo "  ${rel}  migrated (${n} file(s))"
    done

    [[ ${found} -eq 1 ]] || echo "  ${CLR_MUTED}(no legacy clc storage found)${CLR_RESET}"
    echo
}

# ── v2 backups ────────────────────────────────────────────────────────────────
#
# Backup targets (§4.9) are git-config subsections in the clc config file:
#
#   [clc "backup.<name>"]
#       kind = remote | bundle
#       url  = <git remote url>          ; kind=remote
#       path = ~/path/to/store.bundle    ; kind=bundle (stored ~-relative)
#       interval = <seconds>             ; optional per-target debounce override
#
# A successful (non-noop) sync triggers a debounced, backgrounded, fail-safe push
# of the store to every target; `clc backup` forces an immediate synchronous push.
# Two determinism seams keep this snapshot-testable (§6.2): CLC_SYNC_SYNC=1 makes
# the post-sync push run synchronously (capturable); CLC_NOW=<epoch> pins ALL
# wall-clock math (debounce comparison + staleness age). Target names must not
# contain dots so config enumeration stays simple.

# Default debounce when no interval is configured (15 min, §4.9).
CLC_BACKUP_INTERVAL_DEFAULT=900

# Single wall-clock source (§6.2 CLC_NOW seam). ALL time math goes through this.
now_epoch() { echo "${CLC_NOW:-$(date +%s)}"; }

# Expand a leading ~ to $HOME (paths are stored ~-relative; expand at read, §4.5).
expand_tilde() {
    local p="$1"
    case "${p}" in
        "~")    echo "${HOME}" ;;
        # Quote the ~ in the prefix-strip pattern: bash performs tilde expansion
        # inside ${p#~/} otherwise, so the leading ~ would not be stripped.
        "~/"*)  echo "${HOME}/${p#"~/"}" ;;
        *)      echo "${p}" ;;
    esac
}

# Echo configured backup target names, one per line (nothing when none). Derived
# from the `kind` key of each subsection; guarded so a missing config is inert.
backup_targets() {
    git config -f "$(clc_config_file)" --get-regexp '^clc\.backup\.[^.]+\.kind$' 2>/dev/null \
        | awk '{print $1}' | sed -E 's/^clc\.backup\.//; s/\.kind$//' || true
}

# Read a per-target config value (empty + success when missing; safe under set -e).
backup_get() {
    local name="$1" key="$2"
    git config -f "$(clc_config_file)" "clc.backup.${name}.${key}" 2>/dev/null || true
}

# Per-target debounce interval: target override, else global, else the default.
backup_interval() {
    local name="$1" v
    v=$(backup_get "${name}" interval)
    [[ -n "${v}" ]] && { echo "${v}"; return; }
    v=$(config_get clc.backup.interval)
    [[ -n "${v}" ]] && { echo "${v}"; return; }
    echo "${CLC_BACKUP_INTERVAL_DEFAULT}"
}

# Path to a target's last-success stamp (holds the epoch of the last good push).
backup_stamp_file() { echo "$(clc_state_dir)/backup/${1}.stamp"; }

# Return 0 if a target is due (no stamp, or now - stamp >= interval); else 1.
backup_due() {
    local name="$1" stamp interval now last
    stamp="$(backup_stamp_file "${name}")"
    [[ -f "${stamp}" ]] || return 0
    last=$(cat "${stamp}" 2>/dev/null || echo 0)
    [[ -n "${last}" ]] || last=0
    interval=$(backup_interval "${name}")
    now=$(now_epoch)
    [[ $(( now - last )) -ge ${interval} ]]
}

# Append a failure line to the backup log (timestamped via now_epoch) and, only
# in a real interactive context (NOT under the test/determinism seams), optionally
# raise a macOS notification. Tests set CLC_SYNC_SYNC/CLC_NOW, so no notify fires.
backup_log_failure() {
    local name="$1" msg="$2"
    local log; log="$(clc_state_dir)/backup.log"
    mkdir -p "$(dirname "${log}")"
    printf '%s\t%s\t%s\n' "$(now_epoch)" "${name}" "${msg}" >> "${log}"
    if [[ -z "${CLC_SYNC_SYNC:-}" && -z "${CLC_NOW:-}" ]] && command -v osascript >/dev/null 2>&1; then
        osascript -e "display notification \"clc backup '${name}' failed\" with title \"clc\"" \
            >/dev/null 2>&1 || true
    fi
}

# Push the store to one target. Returns 0 on success, 1 on failure. On success,
# rewrites the target's stamp (now_epoch); on failure, logs it.
push_one_target() {
    local name="$1"
    local store kind; store="$(clc_store_dir)"
    kind=$(backup_get "${name}" kind)
    local ok=0
    case "${kind}" in
        remote)
            local url; url=$(backup_get "${name}" url)
            if [[ -z "${url}" ]]; then
                backup_log_failure "${name}" "no url configured"; return 1
            fi
            # clc owns the backup → force-push every branch.
            if git -C "${store}" push --force "${url}" '+refs/heads/*:refs/heads/*' \
                >/dev/null 2>&1; then
                ok=1
            else
                backup_log_failure "${name}" "git push failed (url=${url})"
            fi
            ;;
        bundle)
            local path; path=$(expand_tilde "$(backup_get "${name}" path)")
            if [[ -z "${path}" ]]; then
                backup_log_failure "${name}" "no path configured"; return 1
            fi
            mkdir -p "$(dirname "${path}")"
            if git -C "${store}" bundle create "${path}.tmp" --all >/dev/null 2>&1; then
                # Atomic .prev rotation (§4.9 / Nexus): never leaves zero valid bundles.
                [[ -f "${path}" ]] && mv "${path}" "${path}.prev"
                mv "${path}.tmp" "${path}"
                ok=1
            else
                rm -f "${path}.tmp" 2>/dev/null || true
                backup_log_failure "${name}" "git bundle create failed (path=${path})"
            fi
            ;;
        *)
            backup_log_failure "${name}" "unknown kind '${kind}'"; return 1
            ;;
    esac
    if [[ ${ok} -eq 1 ]]; then
        local stamp; stamp="$(backup_stamp_file "${name}")"
        mkdir -p "$(dirname "${stamp}")"
        now_epoch > "${stamp}"
        return 0
    fi
    return 1
}

# Per-target results from the last push_all_targets, for clc backup's summary.
# Lines: "<name>\t<status>" where status is pushed | failed | skipped.
_BACKUP_RESULTS=()
# Push all targets. force=1 ignores the debounce; force=0 skips non-due targets.
push_all_targets() {
    local force="$1" name
    _BACKUP_RESULTS=()
    while IFS= read -r name; do
        [[ -n "${name}" ]] || continue
        if [[ "${force}" != 1 ]] && ! backup_due "${name}"; then
            _BACKUP_RESULTS+=("${name}"$'\t'"skipped")
            continue
        fi
        if push_one_target "${name}"; then
            _BACKUP_RESULTS+=("${name}"$'\t'"pushed")
        else
            _BACKUP_RESULTS+=("${name}"$'\t'"failed")
        fi
    done < <(backup_targets)
}

# Trigger a debounced backup after a successful sync, ONLY when targets exist.
# CLC_SYNC_SYNC=1 → synchronous (capturable by the harness); otherwise the push
# is backgrounded + fail-safe (§6.2): never blocks/hangs the commit, survives the
# parent exit, leaves no zombies.
maybe_trigger_backup() {
    [[ -n "$(backup_targets)" ]] || return 0
    if [[ -n "${CLC_SYNC_SYNC:-}" ]]; then
        push_all_targets 0
    else
        ( push_all_targets 0 ) >/dev/null 2>&1 & disown 2>/dev/null || true
    fi
}

# Render a last-push age for status, driven by now_epoch (so CLC_NOW pins it).
# "never" when no stamp; otherwise a coarse, deterministic age.
backup_age() {
    local name="$1" stamp last now delta
    stamp="$(backup_stamp_file "${name}")"
    [[ -f "${stamp}" ]] || { echo "never"; return; }
    last=$(cat "${stamp}" 2>/dev/null || echo 0)
    [[ -n "${last}" ]] || last=0
    now=$(now_epoch)
    delta=$(( now - last ))
    [[ ${delta} -lt 0 ]] && delta=0
    if   [[ ${delta} -lt 60    ]]; then echo "just now"
    elif [[ ${delta} -lt 3600  ]]; then echo "$(( delta / 60 ))m ago"
    elif [[ ${delta} -lt 86400 ]]; then echo "$(( delta / 3600 ))h ago"
    else                                echo "$(( delta / 86400 ))d ago"
    fi
}

# `clc backup` — force an immediate synchronous push to ALL targets (ignores the
# debounce). Deterministic per-target summary.
cmd_backup() {
    if [[ -z "$(backup_targets)" ]]; then
        print_header "Backup"
        echo "  ${CLR_MUTED}(no backup targets configured)${CLR_RESET}"
        return 0
    fi
    store_init
    push_all_targets 1

    print_header "Backup"
    local row name status
    for row in ${_BACKUP_RESULTS[@]+"${_BACKUP_RESULTS[@]}"}; do
        IFS=$'\t' read -r name status <<< "${row}"
        case "${status}" in
            pushed) printf "  %s  pushed\n" "${name}" ;;
            failed) print_warning_line "${name}: failed" ;;
            *)      printf "  %s  %s%s%s\n" "${name}" "${CLR_MUTED}" "${status}" "${CLR_RESET}" ;;
        esac
    done
}

# ── v2 sync command (hidden/experimental) ─────────────────────────────────────

# Emit the single non-alarming peer-source warning to STDERR (§6.1). Surfaces
# through the git hook's output even when --from-hook suppresses stdout. No
# absolute paths — only the peer worktree's basename — so it stays deterministic.
warn_peer_source() {
    local current_worktree="$1"
    local name; name=$(basename "${current_worktree}")
    printf '%sclc: synced brain from peer worktree '\''%s'\'' — edit the brain in the main worktree%s\n' \
        "${CLR_WARN}" "${name}" "${CLR_RESET}" >&2
}

# Sync the current worktree's second brain into the central git store (§6.1:
# current-worktree-wins). Hidden/experimental this phase: wired in main()'s
# dispatch but intentionally absent from usage()/--help.
# Snapshot every enrolled repo's brain into the store in one pass (clc save --all).
# Runnable from anywhere (no current repo required). Holds ONE store lock for the
# whole batch and triggers at most one debounced backup at the end.
cmd_sync_all() {
    store_init
    with_store_lock store_sync_all

    print_header "Synced (all enrolled)"
    if [[ ${_SYNC_ALL_ANY} -eq 0 ]]; then
        echo "  ${CLR_MUTED}(nothing enrolled)${CLR_RESET}"
        return 0
    fi
    _print_repo_rows ${_SYNC_ALL_ROWS[@]+"${_SYNC_ALL_ROWS[@]}"}
    [[ ${_SYNC_ALL_SYNCED} -eq 1 ]] && maybe_trigger_backup
    return 0
}

cmd_sync() {
    # --from-hook: run silently + fail-safe (git-hook context must not pollute the
    # user's commit output). The peer warning still goes to stderr (§6.1).
    local from_hook=0 opt_all=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from-hook) from_hook=1 ;;
            -a|--all)    opt_all=1 ;;
            -*) die "unknown option for 'sync': $1" ;;
            *)  die "unexpected argument: $1" ;;
        esac
        shift
    done
    [[ ${from_hook} -eq 1 && ${opt_all} -eq 1 ]] && die "--from-hook and --all are mutually exclusive"
    [[ ${opt_all} -eq 1 ]] && { cmd_sync_all; return; }

    local main_gitdir main_worktree current_worktree
    if [[ ${from_hook} -eq 1 ]]; then
        # GIT_DIR hygiene: git hooks export GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE,
        # which would make clc's CWD-based `git rev-parse` discovery resolve the
        # wrong worktree/gitdir. Unset them so clc rediscovers the repo from the
        # hook's CWD (the worktree that committed). `unset` never errors on a
        # missing var, so this is safe under set -eu.
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX 2>/dev/null || true

        # Fail-safe: any resolution failure exits 0 silently (never break the hook).
        main_gitdir=$(git_main_gitdir)       || exit 0
        main_worktree=$(git_main_worktree "${main_gitdir}") || exit 0
        current_worktree=$(git_current_worktree) || exit 0
        local rel="${main_worktree#${HOME}/}"
        [[ "${rel}" != "${main_worktree}" ]] || exit 0
        # Enrollment gate: a firing hook implies enrollment, but defensively do not
        # resurrect store entries from a stray leftover hook on an unenrolled repo.
        is_enrolled "${main_worktree}" || exit 0
        # Warn (to stderr) when the committing worktree is a peer, not main.
        [[ "${current_worktree}" != "${main_worktree}" ]] && warn_peer_source "${current_worktree}"
        store_init >/dev/null 2>&1 || exit 0
        with_store_lock store_sync_project "${rel}" "${current_worktree}" >/dev/null 2>&1 || true
        # Backup is debounced + backgrounded + fail-safe: a successful sync may
        # trigger a push, but it must never block/hang the commit (§4.9/§6.2).
        [[ "${_STORE_SYNC_RESULT}" == "synced" ]] && maybe_trigger_backup
        exit 0
    fi

    main_gitdir=$(git_main_gitdir)       || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") || die "unable to determine main worktree"
    current_worktree=$(git_current_worktree) || die "unable to determine current worktree"

    # Identity = main worktree's HOME-relative path. Error, never guess, if outside $HOME.
    local rel="${main_worktree#${HOME}/}"
    [[ "${rel}" != "${main_worktree}" ]] || die "project is not under \$HOME — cannot derive store identity"

    # Interactive sync works standalone (no enrollment gate). Warn (to stderr) when
    # syncing from a peer worktree (§6.1); the sync still proceeds.
    [[ "${current_worktree}" != "${main_worktree}" ]] && warn_peer_source "${current_worktree}"

    store_init
    with_store_lock store_sync_project "${rel}" "${current_worktree}"

    print_header "Synced"
    if [[ "${_STORE_SYNC_RESULT}" == "noop" ]]; then
        echo "  ${CLR_MUTED}(store already up to date)${CLR_RESET}"
    else
        local n; n=$(collect_claude_files_in_dir "${current_worktree}" | grep -c . || true)
        echo "  ${n} Claude file(s) → store"
        # Trigger a debounced backup after a real (non-noop) sync (§4.9/§6.2).
        maybe_trigger_backup
    fi
}

# ── v2 cold-start / doctor ────────────────────────────────────────────────────
#
# Cross-machine reconciliation (§6.4). OVERRIDING POLICY: surface, don't
# auto-apply. Invariants: (1) never overwrite or `mv` a non-empty directory;
# (2) never auto-move a code working tree; (3) every reconciliation is an EXPLICIT
# command — `clc doctor` only REPORTS, never acts. All output is content-derived
# (HOME-relative paths + deterministic origins; no SHAs/dates).

# Echo a worktree's configured origin remote URL (empty + success when absent).
repo_origin() {
    git -C "$1" config --get remote.origin.url 2>/dev/null || true
}

# Return 0 if the path is absent OR an empty directory (no entries); else 1.
# bash 3.2-safe: `ls -A` lists all but . and .. — empty output means empty.
dir_is_empty() {
    local path="$1"
    [[ -e "${path}" ]] || return 0
    [[ -d "${path}" ]] || return 1
    [[ -z "$(ls -A "${path}" 2>/dev/null)" ]]
}

# Copy every brain file from the store mirror into a worktree (§6.4 deploy step).
# Only ever COPIES — never deletes worktree files. Safe to run on a fresh clone
# (no brain present) or to re-deploy. No-op when the mirror has no brain files.
deploy_brain() {
    local wt="$1" mirror_dir="$2"
    local f
    while IFS= read -r f; do
        [[ -n "${f}" ]] || continue
        mkdir -p "$(dirname "${wt}/${f}")"
        cp "${mirror_dir}/${f}" "${wt}/${f}"
    done < <(collect_claude_files_in_dir "${mirror_dir}")
}

# `clc doctor` — READ-ONLY health check (§6.4). Reports + suggests; never acts.
cmd_doctor() {
    local store; store="$(clc_store_dir)"
    if [[ ! -d "${store}/.git" || ! -f "$(registry_file)" ]]; then
        print_header "Doctor"
        echo "  ${CLR_MUTED}(no store yet — nothing enrolled)${CLR_RESET}"
        return 0
    fi

    print_header "Doctor"
    local rel origin localpath actual_origin
    while IFS=$'\t' read -r rel origin _rest; do
        [[ -n "${rel}" ]] || continue
        localpath="${HOME}/${rel}"
        if dir_is_empty "${localpath}"; then
            printf "  %s  missing\n" "${rel}"
            printf "      %s(run 'clc clone' / 'clc adopt')%s\n" "${CLR_MUTED}" "${CLR_RESET}"
        else
            actual_origin="$(repo_origin "${localpath}")"
            if [[ -n "${origin}" && "${actual_origin}" != "${origin}" ]]; then
                printf "  %s  origin drift\n" "${rel}"
                printf "      %sregistry: %s%s\n" "${CLR_MUTED}" "${origin}" "${CLR_RESET}"
                printf "      %slocal:    %s%s\n" "${CLR_MUTED}" "${actual_origin}" "${CLR_RESET}"
                printf "      %s(run 'clc relink')%s\n" "${CLR_MUTED}" "${CLR_RESET}"
            else
                printf "  %s  ok\n" "${rel}"
            fi
        fi
    done < <(registry_read)

    # If inside a git repo, also report the current repo if it is locally enrolled
    # (has clc ignore patterns and/or hooks) but is absent from the registry. This
    # is the practical "locally-enrolled repo absent from the registry" check — we
    # cannot scan the whole filesystem.
    local main_gitdir main_worktree
    if main_gitdir=$(git_main_gitdir 2>/dev/null) \
        && main_worktree=$(git_main_worktree "${main_gitdir}" 2>/dev/null); then
        local cur_rel="${main_worktree#${HOME}/}"
        if [[ "${cur_rel}" != "${main_worktree}" ]] && ! is_enrolled "${main_worktree}"; then
            local locally_enrolled=0
            [[ "$(claude_local_ignore_state "${main_gitdir}")" != "no" ]] && locally_enrolled=1
            local h
            for h in ${CLC_HOOKS}; do
                hook_installed "${main_gitdir}" "${h}" && locally_enrolled=1
            done
            if [[ ${locally_enrolled} -eq 1 ]]; then
                printf "  %s  unregistered\n" "${cur_rel}"
                printf "      %s(run 'clc enroll')%s\n" "${CLR_MUTED}" "${CLR_RESET}"
            fi
        fi
    fi
}

# Under-lock helper for relink: rewrite the registry key (old → new) + commit,
# then move the store subtree if tracked (guarded: never clobber a non-empty new
# subtree) + commit.
_store_relink() {
    local old="$1" new="$2" origin="$3"
    local store; store="$(clc_store_dir)"

    # Pre-flight clobber guard: decide whether the old subtree must move and refuse
    # BEFORE mutating anything (so a refused relink leaves the store untouched — no
    # half-rewritten registry). Moving over a non-empty new subtree is refused.
    local move_subtree=0
    if git -C "${store}" ls-files -- "${old}" | grep -q .; then
        move_subtree=1
        if [[ -e "${store}/${new}" ]] && ! dir_is_empty "${store}/${new}"; then
            die "store already has a non-empty subtree at '${new}' — refusing to overwrite"
        fi
    fi

    # Registry re-key.
    registry_remove "${old}"
    registry_add "${new}" "${origin}"
    git -C "${store}" add -- .clc/registry
    git -C "${store}" diff --cached --quiet \
        || git -C "${store}" commit -q -m "relink: ${old} -> ${new}"

    # Move the store subtree (the guard above already passed).
    if [[ ${move_subtree} -eq 1 ]]; then
        mkdir -p "$(dirname "${store}/${new}")"
        git -C "${store}" mv "${old}" "${new}" >/dev/null 2>&1 \
            || die "failed to move store subtree '${old}' -> '${new}'"
        git -C "${store}" diff --cached --quiet \
            || git -C "${store}" commit -q -m "relink: move subtree ${old} -> ${new}"
    fi
}

# `clc relink [<old-home-relative-path>]` — move handling (§4.4 / §6.4).
# Run from the repo's NEW location after moving it.
cmd_relink() {
    local old_arg=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -*) die "unknown option for 'relink': $1" ;;
            *)  if [[ -z "${old_arg}" ]]; then old_arg="$1"
                else die "unexpected argument: $1"
                fi ;;
        esac
        shift
    done

    local main_gitdir main_worktree
    main_gitdir=$(git_main_gitdir)       || die "not inside a Git repository"
    main_worktree=$(git_main_worktree "${main_gitdir}") || die "unable to determine main worktree"

    local new_rel="${main_worktree#${HOME}/}"
    [[ "${new_rel}" != "${main_worktree}" ]] || die "project is not under \$HOME — cannot derive store identity"
    local origin; origin="$(repo_origin "${main_worktree}")"

    [[ -d "$(clc_store_dir)/.git" ]] || die "no store yet — nothing to relink"

    # Determine the OLD registry entry to relink.
    local old=""
    if [[ -n "${old_arg}" ]]; then
        # Explicit old path: must exist in the registry.
        local p _o
        while IFS=$'\t' read -r p _o; do
            [[ "${p}" == "${old_arg}" ]] && { old="${old_arg}"; break; }
        done < <(registry_read)
        [[ -n "${old}" ]] || die "no registry entry for '${old_arg}'"
    else
        # Auto-detect: entries whose origin matches AND whose registered path no
        # longer exists on disk. Require exactly one match.
        local p reg_origin matches=0 candidate=""
        while IFS=$'\t' read -r p reg_origin; do
            [[ -n "${p}" ]] || continue
            [[ "${p}" == "${new_rel}" ]] && continue   # the new location itself
            [[ -n "${origin}" && "${reg_origin}" == "${origin}" ]] || continue
            dir_is_empty "${HOME}/${p}" || continue     # old path gone (absent/empty)
            matches=$(( matches + 1 ))
            candidate="${p}"
        done < <(registry_read)
        if [[ ${matches} -eq 0 ]]; then
            die "could not auto-detect the old path (no matching origin with a vanished path) — pass it explicitly: clc relink <old-home-relative-path>"
        elif [[ ${matches} -gt 1 ]]; then
            die "ambiguous: multiple registry entries match this origin with a vanished path — pass the old path explicitly: clc relink <old-home-relative-path>"
        fi
        old="${candidate}"
    fi

    [[ "${old}" != "${new_rel}" ]] || die "registry already keys this location ('${new_rel}') — nothing to relink"

    with_store_lock _store_relink "${old}" "${new_rel}" "${origin}"

    # Belt-and-suspenders: re-ignore + reinstall hooks at the new gitdir (the moved
    # repo carried its own .git; these are idempotent).
    _ignore_patterns "${main_gitdir}" >/dev/null
    install_hooks "${main_gitdir}"

    print_header "Relinked"
    printf "  %s → %s\n" "${old}" "${new_rel}"
    echo

    cmd_status
}

# Deploy the brain + local-gitignore + install hooks for a cold-start entry.
# Pure side-effect helper shared by clone/adopt. Safe: deploy_brain only copies.
_cold_deploy() {
    local localpath="$1" rel="$2"
    local mirror_dir; mirror_dir="$(clc_store_dir)/${rel}"
    [[ -d "${mirror_dir}" ]] && deploy_brain "${localpath}" "${mirror_dir}"
    local main_gitdir
    if main_gitdir=$(cd "${localpath}" && git_main_gitdir 2>/dev/null); then
        _ignore_patterns "${main_gitdir}" >/dev/null
        install_hooks "${main_gitdir}"
    fi
}

# `clc clone` — guarded cold-start (§6.4). Clones absent/empty entries, adopts
# matching present ones, skips (never clobbers) wrong/unknown dirs.
cmd_clone() {
    local store; store="$(clc_store_dir)"
    if [[ ! -d "${store}/.git" || ! -f "$(registry_file)" ]]; then
        print_header "Clone"
        echo "  ${CLR_MUTED}(no store yet — nothing to clone)${CLR_RESET}"
        return 0
    fi

    print_header "Clone"
    local rel origin localpath actual_origin
    while IFS=$'\t' read -r rel origin _rest; do
        [[ -n "${rel}" ]] || continue
        localpath="${HOME}/${rel}"
        if dir_is_empty "${localpath}"; then
            if [[ -z "${origin}" ]]; then
                printf "  %s  skipped\n" "${rel}"
                print_warning_line "no origin"
                continue
            fi
            # Clone into the empty/absent dir (git clone refuses a non-empty dir).
            if git clone "${origin}" "${localpath}" >/dev/null 2>&1; then
                _cold_deploy "${localpath}" "${rel}"
                printf "  %s  cloned\n" "${rel}"
            else
                printf "  %s  skipped\n" "${rel}"
                print_warning_line "clone failed"
            fi
        else
            actual_origin="$(repo_origin "${localpath}")"
            if [[ -d "${localpath}/.git" || -f "${localpath}/.git" ]] \
                && { [[ -z "${origin}" ]] || [[ "${actual_origin}" == "${origin}" ]]; }; then
                _cold_deploy "${localpath}" "${rel}"
                printf "  %s  adopted\n" "${rel}"
            else
                printf "  %s  skipped\n" "${rel}"
                print_warning_line "exists (skipped, not clc-managed)"
            fi
        fi
    done < <(registry_read)
}

# `clc adopt` — adopt-only cold-start (§6.4). Deploys into present matching repos;
# never clones; reports missing entries; skips wrong/unknown dirs.
cmd_adopt() {
    local store; store="$(clc_store_dir)"
    if [[ ! -d "${store}/.git" || ! -f "$(registry_file)" ]]; then
        print_header "Adopt"
        echo "  ${CLR_MUTED}(no store yet — nothing to adopt)${CLR_RESET}"
        return 0
    fi

    print_header "Adopt"
    local rel origin localpath actual_origin
    while IFS=$'\t' read -r rel origin _rest; do
        [[ -n "${rel}" ]] || continue
        localpath="${HOME}/${rel}"
        if dir_is_empty "${localpath}"; then
            printf "  %s  missing\n" "${rel}"
            printf "      %s(run 'clc clone')%s\n" "${CLR_MUTED}" "${CLR_RESET}"
        else
            actual_origin="$(repo_origin "${localpath}")"
            if [[ -d "${localpath}/.git" || -f "${localpath}/.git" ]] \
                && { [[ -z "${origin}" ]] || [[ "${actual_origin}" == "${origin}" ]]; }; then
                _cold_deploy "${localpath}" "${rel}"
                printf "  %s  adopted\n" "${rel}"
            else
                printf "  %s  skipped\n" "${rel}"
                print_warning_line "exists (skipped, not clc-managed)"
            fi
        fi
    done < <(registry_read)
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
${CLR_BOLD}clc ${CLC_VERSION}${CLR_RESET} - Claude Cloak
Use Claude Code across worktrees without leaving traces.

${CLR_BOLD}Usage:${CLR_RESET} clc [options] [action]

${CLR_BOLD}Options:${CLR_RESET}
  ${CLR_BOLD}-h, --help${CLR_RESET}      Show this help and exit
  ${CLR_BOLD}-V, --version${CLR_RESET}   Show version and exit
      ${CLR_BOLD}--no-color${CLR_RESET}  Disable colored output
      ${CLR_BOLD}--no-gpg${CLR_RESET}    Suppress GPG commit signing

${CLR_BOLD}Actions (Inspect):${CLR_RESET}
  ${CLR_BOLD}status${CLR_RESET}                 Show repository info and managed worktrees ${CLR_MUTED}(default)${CLR_RESET}
  ${CLR_BOLD}ls${CLR_RESET}${CLR_MUTED}|list${CLR_RESET}                List Claude files. Tracked or git-visible
                         files are marked.

${CLR_BOLD}Actions (Claude files):${CLR_RESET}
  ${CLR_BOLD}enroll${CLR_RESET}                 Fully manage this repo: gitignore the Claude files,
                         register it, install sync hooks, and sync the brain
                         into the central store.
  ${CLR_BOLD}unenroll${CLR_RESET}               Reverse enroll: deregister, remove hooks, drop the
                         brain from the store, and un-gitignore the files.
  ${CLR_BOLD}ignore${CLR_RESET}                 Add Claude file patterns to .git/info/exclude
                         ${CLR_MUTED}(gitignore-only; the standalone step within enroll)${CLR_RESET}
  ${CLR_BOLD}unignore${CLR_RESET}               Remove Claude file patterns from .git/info/exclude
                         ${CLR_MUTED}(gitignore-only)${CLR_RESET}
  ${CLR_BOLD}save${CLR_RESET} ${CLR_MUTED}[-a|--all]${CLR_RESET}          Sync Claude files from the current worktree
                         into the central store. ${CLR_MUTED}With --all, snapshot every
                         enrolled repo (runnable from anywhere).${CLR_RESET}
  ${CLR_BOLD}compare${CLR_RESET} ${CLR_MUTED}[-a|--all]${CLR_RESET}       Compare current worktree against the stored
                         state. ${CLR_MUTED}Exits 0 if in sync, 1 if differences exist.
                         With --all, audit every enrolled repo.${CLR_RESET}
  ${CLR_BOLD}diff${CLR_RESET} ${CLR_MUTED}[-a|--all]${CLR_RESET}          Like compare, but prints a full Git diff for all
                         mismatches. ${CLR_MUTED}Exits 0 if in sync, 1 if differences exist.
                         With --all, diff every enrolled repo.${CLR_RESET}
  ${CLR_BOLD}restore${CLR_RESET} ${CLR_MUTED}[-a|--all]${CLR_RESET}       Restore Claude files from the stored state
                         to the current worktree. Prompts before making changes.
                         ${CLR_MUTED}With --all, reconcile every enrolled repo.${CLR_RESET}
  ${CLR_BOLD}backup${CLR_RESET}                 Force an immediate push of the central store to all
                         configured backup targets ${CLR_MUTED}(remote and/or bundle)${CLR_RESET}.

${CLR_BOLD}Actions (Worktrees):${CLR_RESET}
  ${CLR_BOLD}new${CLR_RESET}${CLR_MUTED}|add${CLR_RESET} ${CLR_MUTED}[-n|--no-claude]${CLR_RESET} <name> ${CLR_MUTED}[<branch>]${CLR_RESET}
                         Create a new managed peer worktree and restore Claude
                         files from the stored state. Worktree name
                         derived from <name>: last path component, ticket
                         prefix stripped ${CLR_MUTED}(e.g. feature/PROJ-123_foo → foo)${CLR_RESET}.
                         Branch defaults to <name> as-is; pass <branch> to
                         override. Checks out existing branch or creates new.
  ${CLR_BOLD}rm${CLR_RESET}${CLR_MUTED}|remove${CLR_RESET} ${CLR_MUTED}[-k|--keep-branch]${CLR_RESET} <name>
                         Remove a managed peer worktree and delete its git
                         branch. Fails if the worktree is current or has
                         uncommitted changes.
  ${CLR_BOLD}prune${CLR_RESET}${CLR_MUTED}|clean${CLR_RESET} ${CLR_MUTED}[-k|--keep-branch]${CLR_RESET}
                         Remove all managed peer worktrees that are not current
                         and have no uncommitted changes. Deletes their git
                         branches by default.

${CLR_BOLD}Actions (Transplant):${CLR_RESET}
  ${CLR_BOLD}pull${CLR_RESET} ${CLR_MUTED}[-c|--commit]${CLR_RESET} <name>
                         Transplant all changes from a peer worktree's branch
                         onto the current (primary) branch as staged changes.
                         Rebases the peer branch if needed. Must be run from
                         the main worktree.
  ${CLR_BOLD}close${CLR_RESET} ${CLR_MUTED}[-c|--commit] [-k|--keep-branch]${CLR_RESET} <name>
                         Same as pull, then removes the peer worktree and
                         deletes its branch (like rm).

${CLR_BOLD}Actions (Cross-machine):${CLR_RESET}
  ${CLR_BOLD}doctor${CLR_RESET}                 Report cross-machine drift for every enrolled repo
                         ${CLR_MUTED}(missing / origin drift / unregistered). Read-only;
                         suggests the fix command, never acts.${CLR_RESET}
  ${CLR_BOLD}relink${CLR_RESET} ${CLR_MUTED}[<old-home-relative-path>]${CLR_RESET}
                         Re-key a moved repo: run from its new location to
                         rewrite the registry and move its store subtree.
                         Auto-detects the old path by origin when omitted.
  ${CLR_BOLD}clone${CLR_RESET}                  Cold-start from the restored store: clone each
                         registered repo to its path, deploy the brain, and
                         install hooks. ${CLR_MUTED}Never clobbers a non-empty dir.${CLR_RESET}
  ${CLR_BOLD}adopt${CLR_RESET}                  Like clone but never clones: deploy the brain +
                         hooks only into already-present matching repos.
  ${CLR_BOLD}migrate${CLR_RESET}                One-shot v1→v2: discover repos from the legacy
                         ~/.clc/saved store and enroll the clc-touched ones.
                         ${CLR_MUTED}Idempotent; pre-v2 snapshot history is not replayed.${CLR_RESET}

${CLR_BOLD}Flags:${CLR_RESET}
  ${CLR_BOLD}-k, --keep-branch${CLR_RESET}  ${CLR_MUTED}(rm, prune, close)${CLR_RESET} Keep the worktree's git branch
                     instead of deleting it.
  ${CLR_BOLD}-n, --no-claude${CLR_RESET}    ${CLR_MUTED}(new)${CLR_RESET} Skip restoring Claude files from saved state.
  ${CLR_BOLD}-c, --commit${CLR_RESET}       ${CLR_MUTED}(pull, close)${CLR_RESET} Commit immediately after staging
                     (opens editor with pre-populated message).
  ${CLR_BOLD}-a, --all${CLR_RESET}          ${CLR_MUTED}(save, compare, diff, restore)${CLR_RESET} Operate across every
                     enrolled repo instead of the current one. Runnable anywhere.

${CLR_MUTED}Claude files: CLAUDE.md (any depth), .claude/ (worktree root only).
Managed worktrees: main worktree or peer at <parent>/<main-name>-<worktree-name>.
Run 'clc' without arguments for repository and worktree status.${CLR_RESET}
EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────

main() {
    local action=""
    local -a cmd_args=()
    OPT_NO_COLOR=0
    OPT_NO_GPG=0

    # Pre-scan for --no-color / --no-gpg so globals are ready before usage() or
    # any git command.
    for _arg in "$@"; do
        case "$_arg" in
            --no-color) OPT_NO_COLOR=1 ;;
            --no-gpg)   OPT_NO_GPG=1 ;;
        esac
    done
    setup_color

    # When --no-gpg is passed, suppress GPG commit signing on git commands that
    # create commits (rebase, commit).  Empty array when signing is allowed.
    GIT_SIGN=()
    [[ "${OPT_NO_GPG}" -eq 1 ]] && GIT_SIGN=("-c" "commit.gpgsign=false")

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    usage; exit 0 ;;
            -V|--version) echo "clc ${CLC_VERSION}"; exit 0 ;;
            --no-color)   OPT_NO_COLOR=1 ;;
            --no-gpg)     OPT_NO_GPG=1 ;;
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

    case "${action}" in
        ""|status)    cmd_status ;;
        ls|list)      cmd_ls ;;
        ignore)       cmd_ignore ;;
        unignore)     cmd_unignore ;;
        enroll)       cmd_enroll ;;
        unenroll)     cmd_unenroll ;;
        save)         cmd_sync ${cmd_args[@]+"${cmd_args[@]}"} ;;
        compare)      cmd_compare ${cmd_args[@]+"${cmd_args[@]}"} ;;
        diff)         cmd_diff ${cmd_args[@]+"${cmd_args[@]}"} ;;
        restore)      cmd_restore ${cmd_args[@]+"${cmd_args[@]}"} ;;
        new|add)      cmd_new ${cmd_args[@]+"${cmd_args[@]}"} ;;
        rm|remove)    cmd_rm ${cmd_args[@]+"${cmd_args[@]}"} ;;
        prune|clean)  cmd_prune ${cmd_args[@]+"${cmd_args[@]}"} ;;
        pull)         cmd_pull ${cmd_args[@]+"${cmd_args[@]}"} ;;
        close)        cmd_close ${cmd_args[@]+"${cmd_args[@]}"} ;;
        sync)         cmd_sync ${cmd_args[@]+"${cmd_args[@]}"} ;;
        backup)       cmd_backup ${cmd_args[@]+"${cmd_args[@]}"} ;;
        doctor)       cmd_doctor ${cmd_args[@]+"${cmd_args[@]}"} ;;
        relink)       cmd_relink ${cmd_args[@]+"${cmd_args[@]}"} ;;
        clone)        cmd_clone ${cmd_args[@]+"${cmd_args[@]}"} ;;
        adopt)        cmd_adopt ${cmd_args[@]+"${cmd_args[@]}"} ;;
        migrate)      cmd_migrate ;;
        *) echo "clc: unknown action: ${action}" >&2
           echo "Try 'clc --help' for usage." >&2; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
