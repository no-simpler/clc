#!/usr/bin/env bash
# go-create-existing-branch.sh – Action test: `clc go <branch> --no-launch` where
# the branch exists but has no worktree → silent create (no prompt) under
# .claude/worktrees/<derived>, then status. Branch feature/x → dir name "x".

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/go-create-existing-branch"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – go-create-existing-branch" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

# Branch exists, but no worktree checks it out yet.
git branch feature/x

cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color go feature/x --no-launch
