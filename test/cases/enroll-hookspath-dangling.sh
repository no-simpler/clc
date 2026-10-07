#!/usr/bin/env bash
# enroll-hookspath-dangling.sh – Enroll refuses a core.hooksPath naming a missing dir.
#
# Asserts:
#   1. enroll dies (non-zero) with the dangling-path error + remedies.
#   2. The missing dir is NOT created (no ghost hooks dir).
#   3. Nothing was registered and .git/info/exclude is untouched.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/enroll-hookspath-dangling"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – enroll-hookspath-dangling" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git
echo "# project instructions" > CLAUDE.md
GHOST="${CASE_DIR}/ghost/.git/hooks"
git config core.hooksPath "${GHOST}"

rc=0
"$BASH" "${CLC}" --no-color enroll 2>&1 || rc=$?
echo "exit: ${rc}"

echo
[[ -e "${GHOST}" ]] && echo "ghost dir: created" || echo "ghost dir: absent"
[[ -f "${XDG_DATA_HOME}/clc/store/.clc/registry" ]] && echo "registry: present" || echo "registry: absent"
grep -q CLAUDE .git/info/exclude 2>/dev/null && echo "exclude: patched" || echo "exclude: untouched"
