#!/usr/bin/env bash
# claude-file-states.sh – Exercises the four Claude-file warning states.
#
# Produces in test/playground/claude-file-states/:
#   main/  – main worktree; partial local ignore (CLAUDE.md only, not /.claude/).
#            Holds two managed worktrees under main/.claude/worktrees/:
#              dirty/ – CLAUDE.md tracked + root .gitignore contains CLAUDE.md
#              clean/ – no Claude files, no .gitignore issues
#
# The managed worktrees are nested under .claude/worktrees/, so the runner does
# not auto-snapshot them. Current-worktree-level warnings (which only surface when
# `clc` runs FROM that worktree) are asserted via the ACTION output below: one
# `clc status` per worktree.
#
# Expected (warnings in bold yellow in terminal):
#   From main/    : main-level "Claude files only partially ignored".
#   From dirty/   : main-level partial warning + current-level "Claude files
#                   detected; Claude files in .gitignore".
#   From clean/   : main-level partial warning only (no current-level warnings).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/claude-file-states"
CLC="${REPO_ROOT}/clc.sh"
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

git worktree add -q "${CASE_DIR}/main/.claude/worktrees/dirty" feature/dirty
cd "${CASE_DIR}/main/.claude/worktrees/dirty"

# Force-add: CLAUDE.md is blocked by both .git/info/exclude (partial) and the
# .gitignore we're about to write, so -f is required to create the bad state.
echo "# project instructions" > CLAUDE.md
git add -f CLAUDE.md
echo "CLAUDE.md" > .gitignore
git add .gitignore
${GIT} commit -q -m "Add CLAUDE.md and .gitignore (bad state for demo)"

# ── Managed peer: clean ───────────────────────────────────────────────────────
# No Claude files, no .gitignore issues — only the partial exclude is a problem.

git worktree add -q "${CASE_DIR}/main/.claude/worktrees/clean" feature/clean

# ── Actions: status from each worktree (asserts current-level warnings) ───────

echo "=== status from main ==="
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color status)

echo "=== status from dirty ==="
(cd "${CASE_DIR}/main/.claude/worktrees/dirty" && "$BASH" "${CLC}" --no-color status)

echo "=== status from clean ==="
(cd "${CASE_DIR}/main/.claude/worktrees/clean" && "$BASH" "${CLC}" --no-color status)

