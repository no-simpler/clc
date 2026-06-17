#!/usr/bin/env bash
# save-delete-propagates.sh – Regression: deleting a brain file then saving must
# REMOVE it from the store — both the index AND the working tree — leaving no
# untracked orphan behind (the historical bug: force-remove de-indexed the path but
# the follow-up `git rm` no longer matched, so the file lingered untracked and
# re-propagated on every restore).
#
# Produces in test/playground/save-delete-propagates/:
#   main/  – main worktree; save 3 files, delete one, save again
#
# Asserts:
#   1. After deleting docs/CLAUDE.md and re-saving, the store tracks only 2 files.
#   2. The store working tree holds NO untracked orphan (ls-files --others empty)
#      and the deleted file is physically gone.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/save-delete-propagates"
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
echo "# clc test – save-delete-propagates" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

mkdir -p "${CASE_DIR}/main/.claude" "${CASE_DIR}/main/docs"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"
echo "# nested instructions" > "${CASE_DIR}/main/docs/CLAUDE.md"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save) > /dev/null

# Delete one brain file, then save again — the deletion must propagate to the store.
rm "${CASE_DIR}/main/docs/CLAUDE.md"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save) > /dev/null

STORE="${CLC_STORE}/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

echo "store tracked files after delete+save:"
git -C "${STORE}" ls-files | sed "s|^${PREFIX}/|<project>/|"

echo
echo "untracked orphans in store:"
orphans="$(git -C "${STORE}" ls-files --others --exclude-standard | sed "s|^${PREFIX}/|<project>/|")"
if [[ -z "${orphans}" ]]; then echo "  (none)"; else echo "${orphans}"; fi

echo
echo "deleted file physically present in store?"
if [[ -e "${STORE}/${PREFIX}/docs/CLAUDE.md" ]]; then echo "  yes (BUG)"; else echo "  no"; fi
