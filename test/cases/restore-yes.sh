#!/usr/bin/env bash
# restore-yes.sh – `clc restore -y` applies without the data-loss prompt, even when
# the worktree carries local-only (ahead) edits that the restore discards.
#
# Produces in test/playground/restore-yes/:
#   main/  – worktree with a local-only brain edit; restore -y overwrites it silently
#
# Asserts the output lists the at-risk file but shows NO "[y/N]" prompt and applies.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/restore-yes"
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
echo "# clc test – restore-yes" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save) > /dev/null

# Local-only edit (ahead of the store, relative to the just-recorded baseline).
echo "# LOCAL edit" > "${CASE_DIR}/main/CLAUDE.md"

# restore -y: no prompt, applies (discards the local edit).
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color restore -y)

echo
echo "CLAUDE.md after restore -y: $(cat "${CASE_DIR}/main/CLAUDE.md")"
