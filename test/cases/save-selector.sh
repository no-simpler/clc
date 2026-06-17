#!/usr/bin/env bash
# save-selector.sh – `clc save <selector>` promotes a peer worktree's brain into the
# store AND main (the canonical trunk) from the call site. Run from the MAIN worktree,
# `clc save feat` promotes the *peer's* edits: a clean (uncontested) edit auto-promotes
# with no prompt.
#
# Asserts the peer-only file lands in BOTH the store and main after `clc save feat`,
# and that reconcile then reports no divergence.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/save-selector"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – save-selector" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

mkdir -p "${CASE_DIR}/main/.claude"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

# Peer in sync with the store at creation.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

# A peer-only brain edit (no commit → store untouched until we save it).
mkdir -p "${PEER}/.claude"
echo '{"peer":true}' > "${PEER}/.claude/peer-only.json"

STORE="${XDG_DATA_HOME}/clc/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

echo "1. store before save (peer-only.json absent):"
git -C "${STORE}" ls-files -- "${PREFIX}" | sed "s|^${PREFIX}/|<project>/|"

echo
echo "2. save the peer by selector, from main:"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save feat)

echo
echo "3. store after save (peer-only.json promoted):"
git -C "${STORE}" ls-files -- "${PREFIX}" | sed "s|^${PREFIX}/|<project>/|"

echo
echo "4. main worktree after save (peer-only.json promoted into main too):"
( cd "${CASE_DIR}/main" && ls .claude/peer-only.json 2>&1 )

echo
echo "5. reconcile from main — store and main agree, no divergence:"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color reconcile)
