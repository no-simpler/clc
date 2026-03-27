#!/usr/bin/env bash
# close-basic.sh – Action test: `clc close` transplants + removes worktree.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/close-basic"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# Set up main repo.
git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# close-basic" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# Create peer and make a change.
git worktree add -q "${CASE_DIR}/main-feat" -b feat
echo "feature" > "${CASE_DIR}/main-feat/feature.txt"
git -C "${CASE_DIR}/main-feat" add feature.txt
${GIT} -C "${CASE_DIR}/main-feat" commit -q -m "Add feature"

# Close from main worktree.
cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color close feat | sed -E 's/[0-9a-f]{40}/<sha>/g'

# Verify worktree directory is gone.
echo "--- worktree removed? ---"
[[ ! -d "${CASE_DIR}/main-feat" ]] && echo "yes" || echo "no"

# Verify branch is gone.
echo "--- branch deleted? ---"
git branch --list feat | grep -q feat && echo "no" || echo "yes"
