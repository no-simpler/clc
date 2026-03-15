#!/usr/bin/env bash
# ls-none.sh – No Claude-related files present; clc ls shows <none>.
#
# Produces in test/playground/ls-none/:
#   main/  – main worktree with no Claude files

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/ls-none"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – ls-none" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

(cd "${CASE_DIR}/main" && bash "${CLC}" --no-color ls)
