#!/usr/bin/env bash
# ignore-ignored.sh – Fresh repo; calls `clc ignore`.
#
# Produces in test/playground/ignore-ignored/:
#   main/  – main worktree (branch: main), no pre-existing ignore patterns
#
# Action output: change summary (both patterns added) + status with no warning.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/ignore-ignored"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – ignore-ignored" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color ignore)
