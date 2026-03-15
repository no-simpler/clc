#!/usr/bin/env bash
# ignore-unignored.sh – Repo pre-ignored; calls `clc unignore`.
#
# Produces in test/playground/ignore-unignored/:
#   main/  – main worktree (branch: main), patterns pre-added by setup
#
# Setup silently runs `clc ignore`; action runs `clc unignore`.
# Action output: change summary (both patterns removed) + status with warning.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/ignore-unignored"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
CLC="${REPO_ROOT}/clc.sh"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – ignore-unignored" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# Pre-apply ignore so the repo starts in ignored state (setup, silent)
(cd "${CASE_DIR}/main" && bash "${CLC}" --no-color ignore > /dev/null)

(cd "${CASE_DIR}/main" && bash "${CLC}" --no-color unignore)
