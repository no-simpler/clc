#!/usr/bin/env bash
# restore-addonly.sh – Restore when only storage-only files exist (non-destructive).
#
# Storage has files that don't exist in the worktree; no destructive ops needed.
# Restore should apply without prompting.
#
# Produces in test/playground/restore-addonly/:
#   main/  – empty worktree; restore copies files from storage without prompting

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/restore-addonly"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – restore-addonly" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

# Create Claude files and save them
mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save) > /dev/null

# Remove all Claude files from worktree — storage-only diff, no destructive ops
rm -rf "${CASE_DIR}/main/.claude"
rm "${CASE_DIR}/main/CLAUDE.md"

# Restore should apply without prompting (no stdin needed)
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color restore)
