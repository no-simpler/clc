#!/usr/bin/env bash
# save-full-path.sh – Verify full-path.txt is written to the save_base directory.
#
# Produces in test/playground/save-full-path/:
#   main/  – main worktree; after saving, full-path.txt exists in save_base

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/save-full-path"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – save-full-path" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save) \
    | sed -E 's|/[0-9]{10,}$|/<timestamp>|'

echo "---"
cat "${CASE_DIR}/.clc-store/saved/"*/full-path.txt
