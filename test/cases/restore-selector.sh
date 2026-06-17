#!/usr/bin/env bash
# restore-selector.sh – `clc restore <selector>` takes the stored brain into another
# worktree from the call site. Run from the MAIN worktree, `clc restore feat`
# fast-forwards the *peer's* brain (it is purely behind the store, so it applies as a
# clean update with no prompt).
#
# Setup: peer created in sync, then the store is advanced via a main commit so the
# peer falls behind on CLAUDE.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/restore-selector"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – restore-selector" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

mkdir -p "${CASE_DIR}/main/.claude"
echo "main1" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

# Peer in sync with the store at creation (baseline = store@1).
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

# Advance the store via a main commit: CLAUDE.md → main2 (peer now behind).
cd "${CASE_DIR}/main"
echo "main2" > CLAUDE.md
echo "main change" >> README.md
${GIT} commit -q -am "advance brain in main"

echo "1. peer brain before restore: CLAUDE.md=$(cat "${PEER}/CLAUDE.md")"
echo
echo "2. restore the peer by selector, from main (behind → clean fast-forward):"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color restore feat)
echo
echo "3. peer brain after restore: CLAUDE.md=$(cat "${PEER}/CLAUDE.md")"
