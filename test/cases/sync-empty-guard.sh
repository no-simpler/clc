#!/usr/bin/env bash
# sync-empty-guard.sh – `clc save` refuses to erase a populated store when the
# worktree brain is empty, unless --force-empty is given (the escape hatch).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/sync-empty-guard"
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
echo "# clc test – sync-empty-guard" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

# Save an initial brain into the store.
mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save) > /dev/null

STORE="${CLC_STORE}/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

# Empty the brain on disk.
rm -f "${CASE_DIR}/main/CLAUDE.md"
rm -rf "${CASE_DIR}/main/.claude"

echo "1. 'clc save' with an emptied brain is refused:"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save)

echo
echo "   store still populated:"
git -C "${STORE}" ls-files -- "${PREFIX}" | sed "s|^${PREFIX}/|<project>/|"

echo
echo "2. 'clc save --force-empty' erases the stored brain:"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save --force-empty)

echo
echo "   store after force-empty (no brain files):"
if git -C "${STORE}" ls-files -- "${PREFIX}" | grep -q .; then
    git -C "${STORE}" ls-files -- "${PREFIX}" | sed "s|^${PREFIX}/|<project>/|"
else
    echo "   (empty)"
fi
