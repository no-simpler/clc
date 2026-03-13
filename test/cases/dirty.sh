#!/usr/bin/env bash
# dirty.sh – Sets up a repo state with dirty worktrees for clc verification.
#
# Produces in test/repos/dirty/:
#   main/         – main worktree (branch: main, DIRTY – unstaged change)
#   main-feature/ – managed peer worktree (branch: feature/some-feature, clean)
#   unmanaged/    – unmanaged worktree (detached HEAD, DIRTY – staged change)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/repos/dirty"

# Idempotent cleanup of any previous run
rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# ── Main worktree ──────────────────────────────────────────────────────────────

git init "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main

echo "# clc test – dirty case" > README.md
git add README.md
git -c user.email="clc@test" -c user.name="clc-test" -c commit.gpgsign=false \
    commit -q -m "Initial commit"

# Branch for the managed peer worktree
git branch feature/some-feature

# ── Managed peer worktree ─────────────────────────────────────────────────────

git worktree add -q "${CASE_DIR}/main-feature" feature/some-feature

# ── Unmanaged worktree (detached HEAD) ───────────────────────────────────────

git worktree add -q --detach "${CASE_DIR}/unmanaged"

# ── Make worktrees dirty ──────────────────────────────────────────────────────

# main: unstaged modification
echo "dirty content" >> "${CASE_DIR}/main/README.md"

# unmanaged: staged (indexed) change
echo "new file" > "${CASE_DIR}/unmanaged/staged.txt"
git -C "${CASE_DIR}/unmanaged" add staged.txt

# main-feature: left clean

echo "Repos created in ${CASE_DIR}:"
echo "  main/         (main worktree, branch: main, DIRTY – unstaged)"
echo "  main-feature/ (managed peer, branch: feature/some-feature, clean)"
echo "  unmanaged/    (unmanaged, detached HEAD, DIRTY – staged)"
