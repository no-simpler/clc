#!/usr/bin/env bash
# compare-selector.sh – `clc compare <selector>` compares another worktree's brain
# against the store from the call site. Run from the MAIN worktree, `clc compare
# feat` diffs the *peer's* brain (not main's) and labels it "worktree feat".
#
# Mirrors compare-diffs (all three diff categories), but the divergence lives in a
# peer worktree reached by selector rather than in the current worktree.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/compare-selector"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – compare-selector" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

# Peer with the brain restored (matches the store at creation).
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

# Diverge the peer's brain in all three categories vs the store:
rm "${PEER}/.claude/settings.json"                              # only_storage
echo "# MODIFIED instructions" > "${PEER}/CLAUDE.md"            # different
mkdir -p "${PEER}/docs"
echo "# nested instructions" > "${PEER}/docs/CLAUDE.md"        # only_worktree

echo "1. compare the peer by selector, from main:"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color compare feat) || true

echo
echo "2. compare the (in-sync) main worktree by selector, from the peer:"
(cd "${PEER}" && "$BASH" "${CLC}" --no-color compare main) || true
