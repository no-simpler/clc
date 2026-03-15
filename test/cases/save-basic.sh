#!/usr/bin/env bash
# save-basic.sh – Save Claude files from a worktree to storage.
#
# Produces in test/playground/save-basic/:
#   main/  – main worktree with .claude/settings.json, CLAUDE.md, docs/CLAUDE.md

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/save-basic"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – save-basic" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

bash "${CLC}" --no-color ignore > /dev/null

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"
mkdir -p "${CASE_DIR}/main/docs"
echo "# nested instructions" > "${CASE_DIR}/main/docs/CLAUDE.md"

(cd "${CASE_DIR}/main" && bash "${CLC}" --no-color save) \
    | sed -E 's|/[0-9]{10,}$|/<timestamp>|'
