#!/usr/bin/env bash
# fsck-orphan.sh – `clc fsck` reports an untracked store orphan (debris the old
# orphan-removal bug could leave), and `clc fsck --fix` removes it.
#
# Produces in test/playground/fsck-orphan/:
#   main/  – enrolled main worktree; an untracked orphan is seeded into the store
#
# Asserts:
#   1. `clc fsck` reports the orphan (rel-relative path) and exits 1.
#   2. `clc fsck --fix` removes it; a follow-up fsck reports clean.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/fsck-orphan"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – fsck-orphan" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

# Enroll → registry + initial sync (fsck iterates the registry).
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

STORE="${XDG_DATA_HOME}/clc/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

# Seed an untracked orphan directly into the store working tree (NOT git add'd) —
# exactly the debris the historical bug produced.
echo "# stale" > "${STORE}/${PREFIX}/.claude/ORPHAN.md"

echo "1. fsck (report):"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color fsck) \
    | sed "s|${PREFIX}|<project>|" && echo "   exit=0" || echo "   exit=1"

echo
echo "2. fsck --fix:"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color fsck --fix) \
    | sed "s|${PREFIX}|<project>|"

echo
echo "3. fsck after fix:"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color fsck) | sed "s|${PREFIX}|<project>|"
