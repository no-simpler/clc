#!/usr/bin/env bash
# enroll-hookspath-shared.sh – Enroll stays out of a global core.hooksPath (shared by all repos).
#
# Asserts:
#   1. enroll warns, completes the rest, and reports hooks not installed.
#   2. The global hooks dir stays empty.
#   3. doctor flags the repo with the repo-scoped fix hint.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/enroll-hookspath-shared"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – enroll-hookspath-shared" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git
echo "# project instructions" > CLAUDE.md
SHARED="${CASE_DIR}/.global-hooks"
mkdir -p "${SHARED}"
git config --file "${GIT_CONFIG_GLOBAL}" core.hooksPath "${SHARED}"

"$BASH" "${CLC}" --no-color enroll 2>&1 | sed -n '1,/^$/p'

echo "global hooks dir: $(ls -A "${SHARED}" | wc -l | tr -d ' ') file(s)"
echo
"$BASH" "${CLC}" --no-color doctor
