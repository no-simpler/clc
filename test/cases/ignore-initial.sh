#!/usr/bin/env bash
# ignore-initial.sh – Fresh repo with no ignore setup; status shows warning.
#
# Produces in test/repos/ignore-initial/:
#   main/  – main worktree (branch: main), no patterns in .git/info/exclude

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/repos/ignore-initial"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – ignore-initial" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

echo "Repos created in ${CASE_DIR}:"
echo "  main/  (main worktree, branch: main, no ignore setup)"
