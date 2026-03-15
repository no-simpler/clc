#!/usr/bin/env bash
# prune-with-branch.sh – Action test: `clc prune -b` deletes branches where possible.
#
# main-merged  : clean, same commit as main → removed, branch deleted.
# main-unmerged: clean, unique commit → removed, branch deletion warned.
# main-dirty   : has staged changes → skipped entirely.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/prune-with-branch"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – prune-with-branch" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

git worktree add -q "${CASE_DIR}/main-merged" -b merged

git worktree add -q "${CASE_DIR}/main-unmerged" -b unmerged
echo "unique" > "${CASE_DIR}/main-unmerged/unique.txt"
git -C "${CASE_DIR}/main-unmerged" add unique.txt
${GIT} -C "${CASE_DIR}/main-unmerged" commit -q -m "Unique commit"

git worktree add -q "${CASE_DIR}/main-dirty" -b dirty
echo "change" > "${CASE_DIR}/main-dirty/change.txt"
git -C "${CASE_DIR}/main-dirty" add change.txt

echo "--- prune -b (merged deleted, unmerged warned, dirty skipped) ---"
cd "${CASE_DIR}/main"
bash "${CLC}" --no-color prune -b
