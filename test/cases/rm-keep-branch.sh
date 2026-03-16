#!/usr/bin/env bash
# rm-keep-branch.sh – Action test: `clc rm --keep-branch` removes worktree without deleting branch.
#
# main-merged  : branch at same commit as main → worktree removed, branch kept.
# main-unmerged: branch has unique commit → worktree removed, branch kept.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/rm-keep-branch"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – rm-keep-branch" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# merged: no extra commits.
git worktree add -q "${CASE_DIR}/main-merged" -b merged

# unmerged: add a commit that is not in main.
git worktree add -q "${CASE_DIR}/main-unmerged" -b unmerged
echo "unique" > "${CASE_DIR}/main-unmerged/unique.txt"
git -C "${CASE_DIR}/main-unmerged" add unique.txt
${GIT} -C "${CASE_DIR}/main-unmerged" commit -q -m "Unique commit"

echo "--- rm --keep-branch merged (worktree removed, branch kept) ---"
cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color rm --keep-branch merged

echo "--- rm --keep-branch unmerged (worktree removed, branch kept) ---"
"$BASH" "${CLC}" --no-color rm --keep-branch unmerged
