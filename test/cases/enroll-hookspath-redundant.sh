#!/usr/bin/env bash
# enroll-hookspath-redundant.sh – Enroll unsets a core.hooksPath equal to the repo's own .git/hooks.
#
# Asserts:
#   1. enroll reports the unset and installs hooks.
#   2. core.hooksPath is gone; hooks live in .git/hooks.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/enroll-hookspath-redundant"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – enroll-hookspath-redundant" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git
echo "# project instructions" > CLAUDE.md
mkdir -p .git/hooks
git config core.hooksPath "$(pwd)/.git/hooks"

"$BASH" "${CLC}" --no-color enroll | sed -n '/^Enrolled/,/^$/p'

echo "core.hooksPath: '$(git config --get core.hooksPath || true)'"
echo "hooks present:"
for h in post-commit post-merge post-checkout; do
    [[ -f .git/hooks/${h} ]] && echo "  ${h}"
done
