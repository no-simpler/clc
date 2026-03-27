#!/usr/bin/env bash
# pull-commit.sh – Action test: `clc pull -c` transplants and commits.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/pull-commit"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# Set up main repo.
git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# pull-commit" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# Create peer and make a change.
git worktree add -q "${CASE_DIR}/main-feat" -b feat
echo "committed feature" > "${CASE_DIR}/main-feat/feature.txt"
git -C "${CASE_DIR}/main-feat" add feature.txt
${GIT} -C "${CASE_DIR}/main-feat" commit -q -m "Add feature"

# Pull with --commit (auto-accept editor).
cd "${CASE_DIR}/main"
GIT_EDITOR=true "$BASH" "${CLC}" --no-color --no-gpg pull -c feat \
    | sed -E 's/[0-9a-f]{7,}/<sha>/g'
