#!/usr/bin/env bash
# reconcile-apply.sh – `clc reconcile --apply` resolves a mixed 3-way divergence
# from one place: fast-forward a BEHIND file (take store), auto-promote an AHEAD
# file (→ store + main), and prompt a/b/c for a DIVERGED file.
#
# Produces in test/playground/reconcile-apply/:
#   main/                       – enrolled main worktree
#   main/.claude/worktrees/feat – managed peer with behind + ahead + diverged files
#
# Peer brain edits are made WITHOUT committing (the brain is gitignored), so the
# peer's post-commit hook never auto-promotes them — the divergence is left intact
# for `clc reconcile` to resolve. The store is advanced via main commits (whose
# hook mirrors main → store).
#
# Asserts:
#   1. Read-only `clc reconcile` labels CLAUDE.md behind, a.md ahead, b.md diverged.
#   2. `clc reconcile --apply` (answering 'a' = take store for the diverged b.md)
#      leaves the peer fully in sync: CLAUDE.md taken, a.md promoted, b.md taken.
#   3. The store and the main worktree reflect the promoted a.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/reconcile-apply"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – reconcile-apply" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

mkdir -p "${CASE_DIR}/main/.claude"
echo "main1"  > "${CASE_DIR}/main/CLAUDE.md"
echo "a1"     > "${CASE_DIR}/main/.claude/a.md"
echo "b1"     > "${CASE_DIR}/main/.claude/b.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

# Peer at the nested convention path; baseline = store@1.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

STORE="${XDG_DATA_HOME}/clc/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

# Advance the store via a main commit: CLAUDE.md → main2 (peer will be behind),
# b.md → b2-main (peer will diverge on it). a.md is left untouched in the store.
cd "${CASE_DIR}/main"
echo "main2"   > CLAUDE.md
echo "b2-main" > .claude/b.md
echo "main change" >> README.md
${GIT} commit -q -am "advance brain in main"

# Peer-side brain edits (no commit → no hook): a.md ahead, b.md diverged. CLAUDE.md
# is left at its spawn content (behind the store's main2).
echo "a2-peer" > "${PEER}/.claude/a.md"
echo "b2-peer" > "${PEER}/.claude/b.md"

echo "1. read-only reconcile from the peer:"
(cd "${PEER}" && "$BASH" "${CLC}" --no-color reconcile)

echo
echo "2. reconcile --apply (answer 'a' = take store for diverged b.md):"
printf 'a\n' | (cd "${PEER}" && "$BASH" "${CLC}" --no-color reconcile --apply)

echo
echo "3. resulting peer brain:"
echo "   CLAUDE.md=$(cat "${PEER}/CLAUDE.md")  a.md=$(cat "${PEER}/.claude/a.md")  b.md=$(cat "${PEER}/.claude/b.md")"
echo "   store  a.md=$(git -C "${STORE}" show "HEAD:${PREFIX}/.claude/a.md")  main a.md=$(cat "${CASE_DIR}/main/.claude/a.md")"
