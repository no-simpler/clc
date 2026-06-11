#!/usr/bin/env bash
# save-all.sh – `clc save --all`: snapshot every enrolled repo's brain in one pass.
#
# Three repos enrolled into one (XDG-isolated) store under .repos/ (a dot-dir, so
# the runner does not discover them as worktrees — this case asserts ACTION output
# only). Registry order is sorted, so the per-repo lines are deterministic:
#   gone  – enrolled, then worktree removed → "missing" (skipped, not purged)
#   one   – brain modified after enroll     → "synced"
#   two   – brain untouched after enroll    → "up to date"
#
# Asserts:
#   1. `clc save --all` (run from outside any repo) reports per-repo status.
#   2. A missing repo is skipped and its store subtree is left intact.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/save-all"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

# XDG-isolated store (no CLC_STORE) so the registry holds only these repos. Pin
# store-commit dates defensively so any leaked history stays deterministic.
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}/.repos"

# Enroll a repo with a CLAUDE.md + .claude brain. All repo commits happen BEFORE
# enroll so the installed post-commit hook never fires mid-test.
enroll_repo() {
    local name="$1"
    local wt="${CASE_DIR}/.repos/${name}"
    git init -q "${wt}"
    ( cd "${wt}"
      git checkout -q -b main
      echo "# ${name}" > README.md
      git add README.md
      ${GIT} commit -q -m "Initial commit"
      mkdir -p .claude
      echo '{}' > .claude/settings.json
      echo "# ${name} instructions" > CLAUDE.md
      "$BASH" "${CLC}" --no-color enroll > /dev/null )
}

enroll_repo one
enroll_repo two
enroll_repo gone

# Diverge 'one' from the store (no commit → no hook); remove 'gone' entirely.
echo "# one CHANGED" > "${CASE_DIR}/.repos/one/CLAUDE.md"
rm -rf "${CASE_DIR}/.repos/gone"

# Snapshot every enrolled brain, run from outside any repo.
(cd "${CASE_DIR}" && "$BASH" "${CLC}" --no-color save --all)

# Assert store content deterministically (strip the per-repo subtree prefix).
STORE="${XDG_DATA_HOME}/clc/store"
REL_BASE="${CASE_DIR#${HOME}/}/.repos"
echo
echo "store tracked files:"
git -C "${STORE}" ls-files -- "${REL_BASE}" | sed "s|^${REL_BASE}/||"
