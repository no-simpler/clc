#!/usr/bin/env bash
# sync-basic.sh – Sync the current worktree's second brain into the v2 git store.
#
# Produces in test/playground/sync-basic/:
#   main/  – main worktree with .claude/settings.json, CLAUDE.md, docs/CLAUDE.md
#
# Asserts:
#   1. `clc sync` reports the file count synced to the store.
#   2. A second `clc sync` reports the noop ("store already up to date").
#   3. The store's tracked files (registry + the three brain files, the project
#      subtree prefix stripped) are exactly what we expect.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/sync-basic"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

# Pin store-commit dates defensively (the store stamps its own identity, but pin
# dates so any history that leaks is deterministic). store = XDG_DATA_HOME/clc/store,
# isolated by run.sh; do NOT set CLC_STORE so the data root stays under the playground.
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – sync-basic" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"
mkdir -p "${CASE_DIR}/main/docs"
echo "# nested instructions" > "${CASE_DIR}/main/docs/CLAUDE.md"

# First sync: should report the three files synced.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color sync)

# Second sync: should report the noop.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color sync)

# Assert store content deterministically. STORE resolves the same way clc does:
# clc_data_dir = XDG_DATA_HOME/clc (CLC_STORE unset here), so store = .../clc/store.
STORE="${XDG_DATA_HOME}/clc/store"
# The project subtree prefix is the main worktree's HOME-relative path.
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

echo
echo "store tracked files:"
git -C "${STORE}" ls-files | sed "s|^${PREFIX}/|<project>/|"
