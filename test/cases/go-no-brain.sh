#!/usr/bin/env bash
# go-no-brain.sh – Action test: `clc go <branch> --no-brain --no-launch` creates
# the worktree without restoring the saved brain into it (no "in sync"/restore
# output), even though the store holds a saved brain.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/go-no-brain"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – go-no-brain" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

# Save a brain into the store so a restore WOULD have output if attempted.
mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save) > /dev/null

# Existing branch → silent create; --no-brain skips the restore step entirely.
git branch feature/x
cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color go feature/x --no-brain --no-launch
