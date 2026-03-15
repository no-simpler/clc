#!/usr/bin/env bash
# rm-with-branch.sh – Action test: `clc rm -b` deletes branch after removing worktree.
#
# main-merged  : branch at same commit as main → git branch -d succeeds silently.
# main-unmerged: branch has unique commit → git branch -d fails, warning printed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/rm-with-branch"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – rm-with-branch" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# merged: no extra commits — branch -d will succeed.
git worktree add -q "${CASE_DIR}/main-merged" -b merged

# unmerged: add a commit that is not in main — branch -d will fail.
git worktree add -q "${CASE_DIR}/main-unmerged" -b unmerged
echo "unique" > "${CASE_DIR}/main-unmerged/unique.txt"
git -C "${CASE_DIR}/main-unmerged" add unique.txt
${GIT} -C "${CASE_DIR}/main-unmerged" commit -q -m "Unique commit"

echo "--- rm -b merged (branch deleted) ---"
cd "${CASE_DIR}/main"
bash "${CLC}" --no-color rm -b merged

echo "--- rm -b unmerged (branch not deleted, warning) ---"
bash "${CLC}" --no-color rm -b unmerged
