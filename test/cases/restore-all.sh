#!/usr/bin/env bash
# restore-all.sh – `clc restore --all`: reconcile every enrolled worktree from store.
#
# Two repos enrolled into one (XDG-isolated) store under .repos/ (a dot-dir → not
# discovered as worktrees; asserts ACTION output only). Sorted registry order:
#   clean  – untouched after enroll       → "in sync" one-liner (skipped)
#   drift  – all three diff categories    → header + per-repo restore prompt
#
# The single drifted repo's destructive prompt is confirmed with 'y' on stdin.
# _apply_restore prints relative file names only (no absolute paths), so no path
# normalization is needed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/restore-all"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}/.repos"

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

enroll_repo clean
enroll_repo drift

# Give 'drift' all three diff categories vs the store (no commit → no hook fires):
DRIFT="${CASE_DIR}/.repos/drift"
rm "${DRIFT}/.claude/settings.json"                       # only_storage → re-added
echo "# MODIFIED instructions" > "${DRIFT}/CLAUDE.md"     # different → overwritten
mkdir -p "${DRIFT}/docs"
echo "# nested instructions" > "${DRIFT}/docs/CLAUDE.md"  # only_worktree → removed

# Reconcile every enrolled worktree; confirm the one drifted repo's prompt with 'y'.
echo y | (cd "${CASE_DIR}" && "$BASH" "${CLC}" --no-color restore --all)
