#!/usr/bin/env bash
# rm-foreign.sh – Action test: `clc rm <selector>` refuses a FOREIGN worktree (a
# top-level sibling), pointing the user at `clc name` / `git worktree remove`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/rm-foreign"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – rm-foreign" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

# Foreign worktree: a top-level sibling (not under .claude/worktrees/).
git worktree add -q "${CASE_DIR}/main-legacy" -b feature/legacy

cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color rm feature/legacy 2>&1 || true
