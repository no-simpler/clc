#!/usr/bin/env bash
# rm.sh – Action test: `clc rm` removes a managed peer worktree.
#
# Three invocations:
#   1. clc rm other  (from main)  — fails: dirty
#   2. clc rm feat   (from main-feat) — fails: current worktree
#   3. clc rm feat   (from main)  — succeeds: clean, non-current

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/repos/rm"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – rm" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# Clean peer.
git worktree add -q "${CASE_DIR}/main-feat" -b feat
# Dirty peer (staged change).
git worktree add -q "${CASE_DIR}/main-other" -b other
echo "dirty" > "${CASE_DIR}/main-other/dirty.txt"
git -C "${CASE_DIR}/main-other" add dirty.txt

echo "--- rm dirty peer (fail: uncommitted changes) ---"
cd "${CASE_DIR}/main"
bash "${CLC}" --no-color rm other || true

echo "--- rm current worktree (fail: current) ---"
cd "${CASE_DIR}/main-feat"
bash "${CLC}" --no-color rm feat || true

echo "--- rm clean peer (success) ---"
cd "${CASE_DIR}/main"
bash "${CLC}" --no-color rm feat
