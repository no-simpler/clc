#!/usr/bin/env bash
# claude-file-states.sh – Exercises the four Claude-file warning states.
#
# Produces in test/playground/claude-file-states/:
#   main/       – main worktree; partial local ignore (CLAUDE.md only, not /.claude/)
#   main-dirty/ – managed peer; CLAUDE.md tracked + root .gitignore contains CLAUDE.md
#   main-clean/ – managed peer; no Claude files, no .gitignore issues
#
# Expected output per call site (warnings in bold yellow in terminal):
#
#   From main/:
#     Repository
#       * .../main          (main)
#           Claude files only partially ignored     ← main-level (partial exclude)
#     Managed worktrees ...
#         clean             (feature/clean)
#         dirty             (feature/dirty)
#     Unmanaged worktrees
#       <none>
#
#   From main-dirty/:
#     Repository
#         .../main          (main)
#           Claude files only partially ignored     ← main-level
#     Managed worktrees ...
#         clean             (feature/clean)
#       * dirty             (feature/dirty)
#           Claude files detected; Claude files in .gitignore  ← current-level
#     Unmanaged worktrees
#       <none>
#
#   From main-clean/:
#     Repository
#         .../main          (main)
#           Claude files only partially ignored     ← main-level
#     Managed worktrees ...
#       * clean             (feature/clean)         ← no current-level warnings
#         dirty             (feature/dirty)
#     Unmanaged worktrees
#       <none>

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/claude-file-states"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

# Idempotent cleanup of any previous run
rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# ── Main worktree ─────────────────────────────────────────────────────────────

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main

echo "# clc test – claude-file-states" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

git branch feature/dirty
git branch feature/clean

# Partially ignore Claude files locally: CLAUDE.md only, /.claude/ omitted.
echo "CLAUDE.md" >> .git/info/exclude

# ── Managed peer: dirty ───────────────────────────────────────────────────────
# Has CLAUDE.md tracked and root .gitignore advertising CLAUDE.md.

git worktree add -q "${CASE_DIR}/main-dirty" feature/dirty
cd "${CASE_DIR}/main-dirty"

# Force-add: CLAUDE.md is blocked by both .git/info/exclude (partial) and the
# .gitignore we're about to write, so -f is required to create the bad state.
echo "# project instructions" > CLAUDE.md
git add -f CLAUDE.md
echo "CLAUDE.md" > .gitignore
git add .gitignore
${GIT} commit -q -m "Add CLAUDE.md and .gitignore (bad state for demo)"

# ── Managed peer: clean ───────────────────────────────────────────────────────
# No Claude files, no .gitignore issues — only the partial exclude is a problem.

git worktree add -q "${CASE_DIR}/main-clean" feature/clean

