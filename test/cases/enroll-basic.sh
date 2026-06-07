#!/usr/bin/env bash
# enroll-basic.sh – Fully enroll a repo (gitignore + register + hooks + sync).
#
# Produces in test/playground/enroll-basic/:
#   main/  – main worktree with .claude/settings.json, CLAUDE.md and an origin URL
#
# Asserts:
#   1. `clc enroll` reports registered, hooks installed, and the brain sync.
#   2. .git/info/exclude contains the two CLC patterns.
#   3. The installed post-commit hook contains the sentinels + clc shim
#      (clc path normalized to %%CLC%%).
#   4. The registry lists the project (HOME-relative path) with its origin URL.
#   5. The store tracks the registry + the two brain files (subtree prefix stripped).
#   6. (worktree snapshot) `clc` status shows the new Enrollment section.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/enroll-basic"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

# Pin store-commit dates defensively (store stamps its own identity; pin dates so
# any leaked history is deterministic). store = XDG_DATA_HOME/clc/store (run.sh).
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – enroll-basic" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
# Give the registry line an origin URL. (All commits happen BEFORE enroll so the
# post-commit hook installed by enroll never fires during the test.)
git remote add origin git@example.com:me/proj.git

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

# Enroll (action output).
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll)

# Resolve store + registry the same way clc does (CLC_STORE unset).
STORE="${XDG_DATA_HOME}/clc/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"
MAIN_GITDIR="${CASE_DIR}/main/.git"

echo
echo ".git/info/exclude:"
cat "${MAIN_GITDIR}/info/exclude"

echo
echo "post-commit hook:"
sed "s|${CLC}|%%CLC%%|" "${MAIN_GITDIR}/hooks/post-commit"

echo
echo "registry:"
cat "${STORE}/.clc/registry"

echo
echo "store tracked files:"
git -C "${STORE}" ls-files | sed "s|^${PREFIX}/|<project>/|"
