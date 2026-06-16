#!/usr/bin/env bash
# go-create-preserves-store.sh – Regression test for the v3.0.0 store-wipe bug.
#
# `clc go <newbranch>` runs `git worktree add` under .claude/worktrees/, which
# fires the clc-managed post-checkout hook INSIDE the brand-new, brain-less
# worktree. Before 3.0.1 that hook synced the parent's store subtree from the
# empty worktree and orphan-removed the entire canonical brain; the subsequent
# seed then found a wiped store and restored nothing.
#
# Asserts: after `clc go feat`, (1) the store subtree is INTACT, and (2) the new
# worktree was seeded with the brain.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/go-create-preserves-store"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – go-create-preserves-store" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

# Enroll: installs the hooks (so `git worktree add` will fire post-checkout) and
# does the first sync of the brain into the store.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

STORE="${XDG_DATA_HOME}/clc/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

# Create-and-seed a new worktree. The post-checkout hook fires mid-creation.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

echo "1. store subtree intact after 'clc go' (must list the full brain):"
git -C "${STORE}" ls-files -- "${PREFIX}" | sed "s|^${PREFIX}/|<project>/|"

echo
echo "2. new worktree seeded with the brain:"
[[ -f "${PEER}/CLAUDE.md" ]] && echo "   CLAUDE.md restored" || echo "   CLAUDE.md MISSING"
[[ -f "${PEER}/.claude/settings.json" ]] && echo "   .claude/settings.json restored" || echo "   .claude/settings.json MISSING"
