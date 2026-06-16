#!/usr/bin/env bash
# name-rename.sh – Action test: `clc name <selector> <new-name>` renames a managed
# worktree's DIRECTORY only (branch untouched) via git worktree move, then status.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/name-rename"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – name-rename" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

git worktree add -q "${CASE_DIR}/main/.claude/worktrees/login" -b feature/login

cd "${CASE_DIR}/main"
# Rename the directory login → signin; branch feature/login is untouched.
"$BASH" "${CLC}" --no-color name login signin
