#!/usr/bin/env bash
# prune.sh – Action test: `clc prune` removes all clean non-current peers.
#
# Setup: main + main-clean1 + main-clean2 + main-dirty.
# Prune from main: removes clean1 and clean2; skips dirty (has changes).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/repos/prune"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – prune" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

git worktree add -q "${CASE_DIR}/main-clean1" -b clean1
git worktree add -q "${CASE_DIR}/main-clean2" -b clean2
# Dirty peer: should survive the prune.
git worktree add -q "${CASE_DIR}/main-dirty" -b dirty
echo "change" > "${CASE_DIR}/main-dirty/change.txt"
git -C "${CASE_DIR}/main-dirty" add change.txt

echo "--- prune (removes clean1 and clean2, skips dirty) ---"
cd "${CASE_DIR}/main"
bash "${CLC}" --no-color prune
