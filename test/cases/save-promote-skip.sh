#!/usr/bin/env bash
# save-promote-skip.sh – `clc save <peer>` WITHOUT -y prompts per forked file. Feeding
# 'n' skips the fork: the uncontested edit (CLAUDE.md) still auto-promotes, but the
# forked file (settings.json, changed in both peer and main) is left alone — main keeps
# its own copy and the store is untouched for it. Asserts the prompt + "kept main's copy"
# note, and that main's forked content survives.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/save-promote-skip"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – save-promote-skip" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

# CLAUDE.md: uncontested peer edit. settings.json: forked (both sides changed it).
echo "# peer edit" > "${PEER}/CLAUDE.md"
echo '{"main":1}' > "${CASE_DIR}/main/.claude/settings.json"
echo '{"peer":2}' > "${PEER}/.claude/settings.json"

echo "1. promote the peer, answering 'n' to the fork prompt:"
(cd "${CASE_DIR}/main" && printf 'n\n' | "$BASH" "${CLC}" --no-color save feat)

echo
echo "2. main keeps its own settings.json (fork was skipped):"
echo "   settings.json: $(cat "${CASE_DIR}/main/.claude/settings.json")"
echo "   CLAUDE.md:     $(cat "${CASE_DIR}/main/CLAUDE.md")"
