#!/usr/bin/env bash
# save-selector.sh – `clc save <selector>` promotes another worktree's brain into the
# store from the call site. Run from the MAIN worktree, `clc save feat` syncs the
# *peer's* brain (not main's). As with any peer save, a "main is canonical" nudge
# goes to stderr.
#
# Asserts the peer-only file lands in the store after `clc save feat` from main.

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
