#!/usr/bin/env bash
# new-with-claude-no-save.sh – `clc new --with-claude` when no saved state exists.
#
# --with-claude flag is given but no save exists; should show a muted message
# and continue normally.
#
# Produces in test/playground/new-with-claude-no-save/:
#   main/         – main worktree, no storage
#   main-feature/ – peer worktree created via `clc new --with-claude`

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/new-with-claude-no-save"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – new-with-claude-no-save" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

bash "${CLC}" --no-color ignore > /dev/null

# No save — storage is empty; should show "no saved state" message
bash "${CLC}" --no-color new feature
