#!/usr/bin/env bash
# base.sh – Sets up a baseline repo state for clc verification.
#
# Produces in test/playground/base/:
#   main/       – main worktree (branch: main); holds the managed worktree under
#                 main/.claude/worktrees/feature (branch: feature/some-feature)
#   unmanaged/  – foreign worktree (detached HEAD), a top-level sibling

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/base"

# Idempotent cleanup of any previous run
rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# ── Main worktree ──────────────────────────────────────────────────────────────

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main

echo "# clc test – base case" > README.md
git add README.md
git -c user.email="clc@test" -c user.name="clc-test" -c commit.gpgsign=false \
    commit -q -m "Initial commit"

# Branch for the managed peer worktree
git branch feature/some-feature

# ── Managed worktree (nested under .claude/worktrees/) ────────────────────────

git worktree add -q "${CASE_DIR}/main/.claude/worktrees/feature" feature/some-feature

# ── Foreign worktree (detached HEAD, top-level sibling) ───────────────────────

git worktree add -q --detach "${CASE_DIR}/unmanaged"

