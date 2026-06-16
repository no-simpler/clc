#!/usr/bin/env bash
# name-errors.sh – Action test: `clc name` refuses the current worktree and the
# main worktree.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/name-errors"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – name-errors" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

git worktree add -q "${CASE_DIR}/main/.claude/worktrees/login" -b feature/login

echo "--- rename current worktree (fail) ---"
cd "${CASE_DIR}/main/.claude/worktrees/login"
"$BASH" "${CLC}" --no-color name login other 2>&1 || true

echo "--- rename main worktree (fail) ---"
cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color name main other 2>&1 || true
