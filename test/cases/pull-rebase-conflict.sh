#!/usr/bin/env bash
# pull-rebase-conflict.sh – Action test: `clc pull` with rebase conflict
# aborts cleanly and prints recovery instructions.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/pull-rebase-conflict"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# Set up main repo.
git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "original" > shared.txt
git add shared.txt
${GIT} commit -q -m "Initial commit"

# Create peer and modify the same file.
git worktree add -q "${CASE_DIR}/main-feat" -b feat
echo "peer change" > "${CASE_DIR}/main-feat/shared.txt"
git -C "${CASE_DIR}/main-feat" add shared.txt
${GIT} -C "${CASE_DIR}/main-feat" commit -q -m "Peer modifies shared.txt"

# Advance primary with a conflicting change to the same file.
cd "${CASE_DIR}/main"
echo "primary change" > shared.txt
git add shared.txt
${GIT} commit -q -m "Primary modifies shared.txt"

# Pull — rebase should conflict, abort, and print instructions.
"$BASH" "${CLC}" --no-color --no-gpg pull feat 2>&1 \
    | sed -E 's/[0-9a-f]{7,}/<sha>/g' \
    || true

# Verify both worktrees are clean after abort.
echo "--- main clean? ---"
git -C "${CASE_DIR}/main" status --porcelain | wc -l | tr -d ' '
echo "--- peer clean? ---"
git -C "${CASE_DIR}/main-feat" status --porcelain | wc -l | tr -d ' '
