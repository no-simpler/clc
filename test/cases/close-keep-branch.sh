#!/usr/bin/env bash
# close-keep-branch.sh – Action test: `clc close --keep-branch` preserves branch.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/close-keep-branch"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# Set up main repo.
git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# close-keep-branch" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# Create peer and make a change.
git worktree add -q "${CASE_DIR}/main-feat" -b feat
echo "feature" > "${CASE_DIR}/main-feat/feature.txt"
git -C "${CASE_DIR}/main-feat" add feature.txt
${GIT} -C "${CASE_DIR}/main-feat" commit -q -m "Add feature"

# Close with --keep-branch.
cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color --no-gpg close --keep-branch feat

# Verify worktree is gone but branch remains.
echo "--- worktree removed? ---"
[[ ! -d "${CASE_DIR}/main-feat" ]] && echo "yes" || echo "no"
echo "--- branch still exists? ---"
git branch --list feat | grep -q feat && echo "yes" || echo "no"
