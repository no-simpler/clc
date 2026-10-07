#!/usr/bin/env bash
# relink-hookspath.sh – Relink drops a core.hooksPath that pointed at the old location's .git/hooks.
#
# Produces in test/playground/relink-hookspath/:
#   moved/ – the repo after `mv old moved`
#
# Asserts:
#   1. relink reports the stale-path unset.
#   2. core.hooksPath is gone; hooks present at moved/.git/hooks.
#   3. No ghost dir at the old location.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/relink-hookspath"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/old"
cd "${CASE_DIR}/old"
git checkout -q -b main
echo "# clc test – relink-hookspath" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git
echo "# project instructions" > CLAUDE.md
mkdir -p .git/hooks
git config core.hooksPath "$(pwd)/.git/hooks"
# Enroll would normalize the redundant value; restore it to simulate a repo
# enrolled before this check existed.
"$BASH" "${CLC}" --no-color enroll > /dev/null
git config core.hooksPath "$(pwd)/.git/hooks"

mv "${CASE_DIR}/old" "${CASE_DIR}/moved"
(cd "${CASE_DIR}/moved" && "$BASH" "${CLC}" --no-color relink) | sed -n '/^Relinked/,/^$/p' \
    | sed "s|${CASE_DIR#${HOME}/}|<case>|g"

cd "${CASE_DIR}/moved"
echo "core.hooksPath: '$(git config --get core.hooksPath || true)'"
echo "hooks present:"
for h in post-commit post-merge post-checkout; do
    [[ -f .git/hooks/${h} ]] && echo "  ${h}"
done
[[ -e "${CASE_DIR}/old" ]] && echo "old: recreated" || echo "old: absent"
