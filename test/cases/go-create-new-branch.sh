#!/usr/bin/env bash
# go-create-new-branch.sh – Action test: `clc go <branch> --no-launch` for a
# brand-new branch prompts for confirmation (single keystroke), then creates the
# worktree on the new branch and prints status. 'y' answers the prompt.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/go-create-new-branch"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – go-create-new-branch" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

cd "${CASE_DIR}/main"
# 'spike' is a brand-new branch → confirm prompt; answer 'y' (single keystroke).
printf 'y' | "$BASH" "${CLC}" --no-color go spike --no-launch
