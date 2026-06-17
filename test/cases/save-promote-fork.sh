#!/usr/bin/env bash
# save-promote-fork.sh – `clc save <peer> -y` promotes a peer's edits into store + main
# across the tiered automation:
#   • CLAUDE.md       – peer edited it, main untouched (uncontested) → auto-promote.
#   • settings.json   – BOTH peer and main edited it (a genuine fork) → under -y it is
#                       promoted too (peer wins); without -y it would prompt y/N.
# Asserts both files land in the store AND main, and that reconcile from main and from
# the peer then report in sync (baselines advanced, no divergence, no "no baseline").

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/save-promote-fork"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – save-promote-fork" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

# Peer in sync with the store at creation.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

# CLAUDE.md: peer-only edit (store still equals main → uncontested → auto-promote).
echo "# peer edit" > "${PEER}/CLAUDE.md"

# settings.json: edited in BOTH main (uncommitted → store keeps the old copy) and the
# peer → store != main → a genuine fork.
echo '{"main":1}' > "${CASE_DIR}/main/.claude/settings.json"
echo '{"peer":2}' > "${PEER}/.claude/settings.json"

STORE="${XDG_DATA_HOME}/clc/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

echo "1. promote the peer with -y (fork resolved in the peer's favour):"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save feat -y)

echo
echo "2. store after promote (both files = peer's content):"
echo "   CLAUDE.md:     $(cat "${STORE}/${PREFIX}/CLAUDE.md")"
echo "   settings.json: $(cat "${STORE}/${PREFIX}/.claude/settings.json")"

echo
echo "3. main after promote (both files = peer's content):"
echo "   CLAUDE.md:     $(cat "${CASE_DIR}/main/CLAUDE.md")"
echo "   settings.json: $(cat "${CASE_DIR}/main/.claude/settings.json")"

echo
echo "4. reconcile from main — in sync:"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color reconcile)

echo
echo "5. reconcile from the peer — in sync:"
(cd "${PEER}" && "$BASH" "${CLC}" --no-color reconcile)
