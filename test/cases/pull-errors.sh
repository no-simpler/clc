#!/usr/bin/env bash
# pull-errors.sh – Action test: `clc pull` error conditions.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/pull-errors"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# Set up main repo.
git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# pull-errors" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# Create clean peer.
git worktree add -q "${CASE_DIR}/main-clean" -b clean
echo "work" > "${CASE_DIR}/main-clean/work.txt"
git -C "${CASE_DIR}/main-clean" add work.txt
${GIT} -C "${CASE_DIR}/main-clean" commit -q -m "Work"

# Create dirty peer.
git worktree add -q "${CASE_DIR}/main-dirty" -b dirty
echo "uncommitted" > "${CASE_DIR}/main-dirty/dirty.txt"
git -C "${CASE_DIR}/main-dirty" add dirty.txt

echo "--- pull from peer worktree (fail: not main) ---"
cd "${CASE_DIR}/main-clean"
"$BASH" "${CLC}" --no-color pull clean || true

echo "--- pull unknown peer (fail: not found) ---"
cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color pull nonexistent || true

echo "--- pull dirty peer (fail: uncommitted) ---"
cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color pull dirty || true

echo "--- pull with dirty main (fail: uncommitted) ---"
echo "dirty" > "${CASE_DIR}/main/dirty.txt"
git -C "${CASE_DIR}/main" add dirty.txt
cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color pull clean || true
git -C "${CASE_DIR}/main" reset -q HEAD -- dirty.txt
rm -f "${CASE_DIR}/main/dirty.txt"

echo "--- pull identical branch (fail: nothing to transplant) ---"
# Create a peer that points to same commit as main.
git worktree add -q "${CASE_DIR}/main-same" -b same
cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color pull same || true
