#!/usr/bin/env bash
# name-migrate-sibling.sh – Action test: `clc name` adopts a FOREIGN worktree (a
# legacy v2 top-level sibling) into the managed location under
# .claude/worktrees/<new-name>. After the move the sibling dir no longer exists,
# so its auto-generated top-level snapshot is deleted (see test/run.sh notes).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/name-migrate-sibling"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – name-migrate-sibling" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

# Legacy v2 sibling: a foreign worktree at the top level (not under .claude/).
git worktree add -q "${CASE_DIR}/main-legacy" -b feature/legacy

cd "${CASE_DIR}/main"
# Adopt the foreign worktree into the managed location, renaming to "adopted".
"$BASH" "${CLC}" --no-color name feature/legacy adopted
