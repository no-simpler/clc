#!/usr/bin/env bash
# unenroll-basic.sh – Enroll a repo then fully unenroll it; assert clean reversal.
#
# Produces in test/playground/unenroll-basic/:
#   main/  – main worktree, enrolled then unenrolled
#
# Asserts:
#   1. `clc unenroll` reports the reversal.
#   2. .git/info/exclude no longer contains the CLC patterns.
#   3. The three hook files are gone (clc created them, only the shim remained).
#   4. The registry no longer lists the project.
#   5. The store no longer tracks the project subtree.
#   6. (worktree snapshot) `clc` status has no Enrollment section.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/unenroll-basic"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – unenroll-basic" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

# Enroll silently, then unenroll (action output). No commits after enroll so the
# installed post-commit hook never fires during the test.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll > /dev/null)
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color unenroll)

STORE="${XDG_DATA_HOME}/clc/store"
MAIN_GITDIR="${CASE_DIR}/main/.git"

echo
echo ".git/info/exclude contains CLC patterns:"
if grep -qxF "CLAUDE.md" "${MAIN_GITDIR}/info/exclude" 2>/dev/null \
   || grep -qxF "/.claude/" "${MAIN_GITDIR}/info/exclude" 2>/dev/null; then
    echo "  yes"
else
    echo "  no"
fi

echo
echo "hook files present:"
for h in post-commit post-merge post-checkout; do
    if [[ -f "${MAIN_GITDIR}/hooks/${h}" ]]; then
        echo "  ${h}: yes"
    else
        echo "  ${h}: no"
    fi
done

echo
echo "registry:"
cat "${STORE}/.clc/registry"

echo
echo "store tracked files:"
git -C "${STORE}" ls-files
