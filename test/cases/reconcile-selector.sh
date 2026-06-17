#!/usr/bin/env bash
# reconcile-selector.sh – `clc reconcile <selector>` targets another worktree from
# the call site. Run from the MAIN worktree, `clc reconcile feat` classifies the
# *peer's* brain against the store (not main's), and `--apply` resolves the peer.
#
# The peer is created with --no-brain, so it is purely BEHIND the store (which holds
# main's brain); main itself is in sync. Mirrors reconcile-3way, but invokes from
# main with the peer selector instead of cd-ing into the peer.
#
# Asserts:
#   1. `clc reconcile feat` from main shows the peer (labelled "worktree feat")
#      behind, plus the main↔store context row (in sync).
#   2. `clc reconcile feat --apply` from main fast-forwards the peer's brain.
#   3. The peer's brain afterwards matches main's.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/reconcile-selector"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – reconcile-selector" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

# Peer created with --no-brain: brain absent → purely behind the store.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-brain --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

echo "1. reconcile the peer by selector, from main (peer behind; main in sync):"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color reconcile feat)

echo
echo "2. reconcile --apply the peer by selector, from main:"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color reconcile feat --apply)

echo
echo "3. peer brain after apply:"
echo "   CLAUDE.md=$(cat "${PEER}/CLAUDE.md")  settings=$(cat "${PEER}/.claude/settings.json")"
