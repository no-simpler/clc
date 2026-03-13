#!/usr/bin/env bash
# ignore-ignored.sh – Fresh repo; test runner invokes `clc ignore`.
#
# Produces in test/repos/ignore-ignored/:
#   main/  – main worktree (branch: main), no pre-existing ignore patterns
#
# .clc_cmd in main/ tells the runner to call `clc ignore` instead of `clc status`.
# Expected output: change summary (both patterns added) + status with no warning.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/repos/ignore-ignored"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – ignore-ignored" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

echo "Repos created in ${CASE_DIR}:"
echo "  main/  (main worktree, branch: main)"
