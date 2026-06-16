#!/usr/bin/env bash
# go-create-collision.sh – Action test: `clc go <selector>` whose derived dir name
# collides with an existing managed worktree dies with a "did you mean" error.
# A managed worktree 'login' exists; `clc go feature/AOE-53-login` derives "login"
# (path component + ticket prefix stripped) → collision.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/go-create-collision"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – go-create-collision" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

git worktree add -q "${CASE_DIR}/main/.claude/worktrees/login" -b feature/login

cd "${CASE_DIR}/main"
# Derives "login" → collides with the existing managed worktree dir.
"$BASH" "${CLC}" --no-color go feature/AOE-53-login 2>&1 || true
