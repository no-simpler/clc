#!/usr/bin/env bash
# restore-sync.sh – Restore with diffs; user confirms synchronization.
#
# Produces in test/playground/restore-sync/:
#   main/  – worktree diverged from storage; restore with y synchronizes it

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/restore-sync"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – restore-sync" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

bash "${CLC}" --no-color ignore > /dev/null

# Initial Claude files for save snapshot
mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

# Save silently
(cd "${CASE_DIR}/main" && bash "${CLC}" --no-color save) > /dev/null

# Create all three diff categories (same as compare-diffs):
rm "${CASE_DIR}/main/.claude/settings.json"
echo "# MODIFIED instructions" > "${CASE_DIR}/main/CLAUDE.md"
mkdir -p "${CASE_DIR}/main/docs"
echo "# nested instructions" > "${CASE_DIR}/main/docs/CLAUDE.md"

echo y | (cd "${CASE_DIR}/main" && bash "${CLC}" --no-color restore)
