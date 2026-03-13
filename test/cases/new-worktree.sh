#!/usr/bin/env bash
# new-worktree.sh – Action test: `clc new` derives worktree name and branch.
#
# Three invocations:
#   1. clc new feature/PROJ-123_my-feature
#      worktree name: my-feature  (path stripped, ticket prefix stripped)
#      branch:        feature/PROJ-123_my-feature  (full first arg)
#   2. clc new PROJ-456-widget explicit-branch
#      worktree name: widget  (ticket prefix stripped)
#      branch:        explicit-branch  (explicit second arg)
#   3. clc new simple-task
#      worktree name: simple-task  (no stripping needed)
#      branch:        simple-task  (full first arg = worktree name)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/repos/new-worktree"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – new-worktree" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

echo "--- path + ticket prefix stripped; branch = full first arg ---"
bash "${CLC}" --no-color new feature/PROJ-123_my-feature

echo "--- ticket prefix stripped; explicit branch override ---"
bash "${CLC}" --no-color new PROJ-456-widget explicit-branch

echo "--- plain name; branch = name ---"
bash "${CLC}" --no-color new simple-task
