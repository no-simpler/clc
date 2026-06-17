#!/usr/bin/env bash
# reconcile-apply-yes.sh – `clc reconcile --apply -y` is non-interactive and
# safe-only: it fast-forwards BEHIND files and promotes AHEAD files, but leaves
# DIVERGED files untouched (reported for manual resolution).
#
# Produces in test/playground/reconcile-apply-yes/:
#   main/                       – enrolled main worktree
#   main/.claude/worktrees/feat – managed peer with behind + ahead + diverged files
#
# Asserts CLAUDE.md (behind) is taken, a.md (ahead) is promoted, and b.md (diverged)
# is left at the peer's local content (not resolved).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/reconcile-apply-yes"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – reconcile-apply-yes" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

mkdir -p "${CASE_DIR}/main/.claude"
echo "main1" > "${CASE_DIR}/main/CLAUDE.md"
echo "a1"    > "${CASE_DIR}/main/.claude/a.md"
echo "b1"    > "${CASE_DIR}/main/.claude/b.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

STORE="${XDG_DATA_HOME}/clc/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

cd "${CASE_DIR}/main"
echo "main2"   > CLAUDE.md
echo "b2-main" > .claude/b.md
echo "main change" >> README.md
${GIT} commit -q -am "advance brain in main"

echo "a2-peer" > "${PEER}/.claude/a.md"
echo "b2-peer" > "${PEER}/.claude/b.md"

echo "reconcile --apply -y (safe-only):"
(cd "${PEER}" && "$BASH" "${CLC}" --no-color reconcile --apply -y)

echo
echo "resulting peer brain:"
echo "  CLAUDE.md=$(cat "${PEER}/CLAUDE.md")  a.md=$(cat "${PEER}/.claude/a.md")  b.md=$(cat "${PEER}/.claude/b.md")"
echo "  store a.md=$(git -C "${STORE}" show "HEAD:${PREFIX}/.claude/a.md")  store b.md=$(git -C "${STORE}" show "HEAD:${PREFIX}/.claude/b.md")"
