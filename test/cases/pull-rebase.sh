#!/usr/bin/env bash
# pull-rebase.sh – Action test: `clc pull` rebases peer branch when primary
# has advanced, then transplants changes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/pull-rebase"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# Set up main repo.
git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# pull-rebase" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# Create peer and make a change.
git worktree add -q "${CASE_DIR}/main-feat" -b feat
echo "feature work" > "${CASE_DIR}/main-feat/feature.txt"
git -C "${CASE_DIR}/main-feat" add feature.txt
${GIT} -C "${CASE_DIR}/main-feat" commit -q -m "Add feature"

# Advance primary with a non-conflicting change.
cd "${CASE_DIR}/main"
echo "primary advance" > other.txt
git add other.txt
${GIT} commit -q -m "Advance primary"

# Pull — should rebase peer first.
"$BASH" "${CLC}" --no-color pull feat
