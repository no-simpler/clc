#!/usr/bin/env bash
# pull-basic.sh – Action test: `clc pull` transplants changes from a peer
# whose branch is already on top of primary (no rebase needed).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/pull-basic"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# Set up main repo with initial commit.
git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# pull-basic" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# Create peer worktree and make a change.
git worktree add -q "${CASE_DIR}/main-feat" -b feat
echo "new feature" > "${CASE_DIR}/main-feat/feature.txt"
git -C "${CASE_DIR}/main-feat" add feature.txt
${GIT} -C "${CASE_DIR}/main-feat" commit -q -m "Add feature"

# Pull from main worktree.
cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color pull feat
