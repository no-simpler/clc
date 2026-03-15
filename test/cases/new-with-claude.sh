#!/usr/bin/env bash
# new-with-claude.sh – Action test: `clc new --with-claude` restores Claude files.
#
# Storage has Claude files saved. New worktree is created with --with-claude;
# files from storage are applied without prompting (storage-only, non-destructive).
#
# Produces in test/playground/new-with-claude/:
#   main/         – main worktree with saved Claude files
#   main-feature/ – peer worktree created via `clc new --with-claude`

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/new-with-claude"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – new-with-claude" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

bash "${CLC}" --no-color ignore > /dev/null

# Save Claude files to storage
mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"
(cd "${CASE_DIR}/main" && bash "${CLC}" --no-color save) > /dev/null

# Create new worktree; should auto-restore without prompt (default behavior)
bash "${CLC}" --no-color new feature
