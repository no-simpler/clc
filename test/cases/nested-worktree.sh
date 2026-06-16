#!/usr/bin/env bash
# nested-worktree.sh – Verify that a linked git worktree nested under .claude/
# (as created by Claude Code's worktree feature, at .claude/worktrees/<name>) is
# treated as a separate project and excluded from the outer repo's second brain.
#
# Produces in test/playground/nested-worktree/:
#   parent/ – repo whose .claude/worktrees/wt-a holds a full linked worktree
#
# Tests:
#   1. clc ls   from parent lists only the real brain (no .claude/worktrees/** files)
#   2. clc save from parent stores only the real brain (no nested-worktree files)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/nested-worktree"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# ── Create the parent repo ──────────────────────────────────────────────────

git init -q "${CASE_DIR}/parent"
cd "${CASE_DIR}/parent"
git checkout -q -b main
echo "# parent" > README.md
git add README.md
${GIT} commit -q -m "Initial parent commit"

# Locally ignore Claude files
"$BASH" "${CLC}" --no-color ignore > /dev/null

# ── Real brain files ────────────────────────────────────────────────────────

echo "# parent instructions" > "${CASE_DIR}/parent/CLAUDE.md"
mkdir -p "${CASE_DIR}/parent/.claude/rules"
echo '{}' > "${CASE_DIR}/parent/.claude/settings.json"
echo "# rule" > "${CASE_DIR}/parent/.claude/rules/x.md"

# ── Nested linked worktree under .claude/worktrees/<name> ───────────────────

# A second branch with a commit, checked out as a linked worktree inside .claude/.
echo "# on feature branch" > extra.txt
git add extra.txt
${GIT} commit -q -m "extra file on main"
git -c core.hooksPath=/dev/null worktree add -q -b feature/x \
    "${CASE_DIR}/parent/.claude/worktrees/wt-a" main

# Drop brain-shaped and ordinary files inside the nested worktree; none of these
# belong to the parent's brain.
echo "# nested wt instructions" > "${CASE_DIR}/parent/.claude/worktrees/wt-a/CLAUDE.md"
mkdir -p "${CASE_DIR}/parent/.claude/worktrees/wt-a/.claude"
echo '{}' > "${CASE_DIR}/parent/.claude/worktrees/wt-a/.claude/settings.json"
echo "junk" > "${CASE_DIR}/parent/.claude/worktrees/wt-a/some-source.txt"

# ── Actions ─────────────────────────────────────────────────────────────────

echo "=== ls from parent ==="
(cd "${CASE_DIR}/parent" && "$BASH" "${CLC}" --no-color ls)

echo ""
echo "=== save from parent ==="
(cd "${CASE_DIR}/parent" && "$BASH" "${CLC}" --no-color save)
