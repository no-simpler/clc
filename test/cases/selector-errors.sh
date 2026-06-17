#!/usr/bin/env bash
# selector-errors.sh – the brain-family <selector> rejects bad input the same way
# rm/name/pull/close do: a no-match selector and an ambiguous prefix both die
# (resolution-only — never creates a worktree), and a selector combined with --all
# is a usage error.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/selector-errors"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – selector-errors" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

mkdir -p "${CASE_DIR}/main/.claude"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

# Two peers whose names share the prefix "feature" → ambiguous prefix selector.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feature-a -y --no-launch) > /dev/null 2>&1
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feature-b -y --no-launch) > /dev/null 2>&1

echo "1. reconcile with a no-match selector:"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color reconcile bogus) 2>&1 || echo "   (exit $?)"

echo
echo "2. reconcile with an ambiguous prefix selector:"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color reconcile feature) 2>&1 || echo "   (exit $?)"

echo
echo "3. compare with --all and a selector together:"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color compare --all feature-a) 2>&1 || echo "   (exit $?)"
