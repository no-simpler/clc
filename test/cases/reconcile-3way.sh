#!/usr/bin/env bash
# reconcile-3way.sh – Action test: `clc reconcile` shows the read-only 3-way view
# of the brain across the current worktree, the store, and the main worktree.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/reconcile-3way"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – reconcile-3way" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

# A peer created with --no-brain: its brain is absent, so it is purely behind the
# store (which holds main's brain); main itself is in sync.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-brain --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

echo "reconcile from the peer (brain missing → behind; main in sync):"
(cd "${PEER}" && "$BASH" "${CLC}" --no-color reconcile)
