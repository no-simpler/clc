#!/usr/bin/env bash
# dirty.sh – Sets up a repo state with dirty worktrees for clc verification.
#
# Produces in test/playground/dirty/:
#   main/         – main worktree (branch: main, DIRTY – unstaged change); holds
#                   the managed worktree under main/.claude/worktrees/feature
#                   (branch: feature/some-feature, clean)
#   unmanaged/    – foreign worktree (detached HEAD, DIRTY – staged change)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/dirty"

# Idempotent cleanup of any previous run
rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# ── Main worktree ──────────────────────────────────────────────────────────────

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main

echo "# clc test – dirty case" > README.md
git add README.md
git -c user.email="clc@test" -c user.name="clc-test" -c commit.gpgsign=false \
    commit -q -m "Initial commit"

# Branch for the managed peer worktree
git branch feature/some-feature

# ── Managed worktree (nested under .claude/worktrees/) ────────────────────────

git worktree add -q "${CASE_DIR}/main/.claude/worktrees/feature" feature/some-feature

# ── Foreign worktree (detached HEAD, top-level sibling) ───────────────────────

git worktree add -q --detach "${CASE_DIR}/unmanaged"

# ── Make worktrees dirty ──────────────────────────────────────────────────────

# main: unstaged modification
echo "dirty content" >> "${CASE_DIR}/main/README.md"

# unmanaged: staged (indexed) change
echo "new file" > "${CASE_DIR}/unmanaged/staged.txt"
git -C "${CASE_DIR}/unmanaged" add staged.txt

# managed feature worktree: left clean

