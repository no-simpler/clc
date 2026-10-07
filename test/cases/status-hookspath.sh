#!/usr/bin/env bash
# status-hookspath.sh – Status and doctor report misconfigured core.hooksPath.
#
# Produces in test/playground/status-hookspath/:
#   dangling/  – enrolled, then core.hooksPath pointed at a missing dir
#   redundant/ – enrolled, then core.hooksPath set to its own .git/hooks
#
# Asserts:
#   1. (worktree snapshots) status warns in the Enrollment section.
#   2. doctor flags both repos with a fix hint, read-only (no dir created).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/status-hookspath"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/dangling"
cd "${CASE_DIR}/dangling"
git checkout -q -b main
echo "# clc test – status-hookspath" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git
echo "# project instructions" > CLAUDE.md
"$BASH" "${CLC}" --no-color enroll > /dev/null
git config core.hooksPath "${CASE_DIR}/nowhere"

git init -q "${CASE_DIR}/redundant"
cd "${CASE_DIR}/redundant"
git checkout -q -b main
echo "# clc test – status-hookspath" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/other.git
"$BASH" "${CLC}" --no-color enroll > /dev/null
git config core.hooksPath "$(pwd)/.git/hooks"

"$BASH" "${CLC}" --no-color doctor
echo
[[ -e "${CASE_DIR}/nowhere" ]] && echo "nowhere: created" || echo "nowhere: absent"
