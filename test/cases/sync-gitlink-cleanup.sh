#!/usr/bin/env bash
# sync-gitlink-cleanup.sh – A stale nested-worktree gitlink (mode 160000) that
# leaked into a project's store subtree is swept on the next sync. Plain `git rm`
# exits 128 on a 160000 entry, so store_sync_project uses `update-index
# --force-remove`; this asserts the debris is actually removed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/sync-gitlink-cleanup"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – sync-gitlink-cleanup" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save) > /dev/null

STORE="${CLC_STORE}/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

# Inject a stale gitlink into the project's store subtree (simulating an old
# nested-worktree leak), then commit it.
GHOST_SHA="$(git -C "${STORE}" rev-parse HEAD)"
git -C "${STORE}" update-index --add --cacheinfo "160000,${GHOST_SHA},${PREFIX}/.claude/worktrees/ghost"
git -C "${STORE}" commit -q -m "seed stale gitlink"

echo "1. store subtree BEFORE cleanup (carries the stale gitlink):"
git -C "${STORE}" ls-files -- "${PREFIX}" | sed "s|^${PREFIX}/|<project>/|"

# A normal save from main must sweep the orphan gitlink.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save) > /dev/null 2>&1

echo
echo "2. store subtree AFTER save (gitlink gone, brain intact):"
git -C "${STORE}" ls-files -- "${PREFIX}" | sed "s|^${PREFIX}/|<project>/|"
