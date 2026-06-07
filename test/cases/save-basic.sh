#!/usr/bin/env bash
# save-basic.sh – Save (= sync) Claude files from a worktree into the git store.
#
# `clc save` is an alias for `clc sync`: it mirrors the current worktree's second
# brain into the central git store (the HEAD-committed mirror), reporting the file
# count. A second save reports the noop.
#
# Produces in test/playground/save-basic/:
#   main/  – main worktree with .claude/settings.json, CLAUDE.md, docs/CLAUDE.md
#
# Asserts:
#   1. `clc save` reports the three files synced to the store.
#   2. A second `clc save` reports the noop ("store already up to date").
#   3. The store's tracked files (the three brain files, project subtree prefix
#      stripped) are exactly what we expect.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/save-basic"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

# Pin store-commit dates defensively (the store stamps its own identity, but pin
# dates so any history that leaks is deterministic).
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – save-basic" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"
mkdir -p "${CASE_DIR}/main/docs"
echo "# nested instructions" > "${CASE_DIR}/main/docs/CLAUDE.md"

# First save: should report the three files synced.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save)

# Second save: should report the noop.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save)

# Assert store content deterministically. With CLC_STORE set, the data root is
# CLC_STORE, so the store git repo lives at CLC_STORE/store.
STORE="${CLC_STORE}/store"
# The project subtree prefix is the main worktree's HOME-relative path.
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

echo
echo "store tracked files:"
git -C "${STORE}" ls-files | sed "s|^${PREFIX}/|<project>/|"
