#!/usr/bin/env bash
# backup-remote.sh – Backup the central store to a git remote target (P6).
#
# Produces in test/playground/backup-remote/:
#   main/        – main worktree with a brain, synced into the store
#   .remote/remote.git/  – a bare repo serving as the backup remote (dot-dir so
#                          the runner's worktree discovery skips it)
#
# Asserts:
#   1. `clc backup` (force) reports the remote target pushed.
#   2. The bare remote received the store's branch (deterministic OK line).
#
# Determinism seams (§6.2): CLC_SYNC_SYNC=1, CLC_NOW=<fixed>. store =
# XDG_DATA_HOME/clc/store (isolated by run.sh); CLC_STORE intentionally unset.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/backup-remote"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
export CLC_SYNC_SYNC=1
export CLC_NOW=1700000000

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# Bare repo to receive the backup push.
git init -q --bare "${CASE_DIR}/.remote/remote.git"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – backup-remote" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

# Sync the brain into the store.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color sync > /dev/null)

# Configure a remote target pointing at the bare repo.
mkdir -p "${XDG_CONFIG_HOME}/clc"
git config -f "${XDG_CONFIG_HOME}/clc/config" clc.backup.r1.kind remote
git config -f "${XDG_CONFIG_HOME}/clc/config" clc.backup.r1.url "${CASE_DIR}/.remote/remote.git"

# Force a backup (synchronous). Should report pushed.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color backup)

# The store's current branch should now exist in the bare remote.
STORE="${XDG_DATA_HOME}/clc/store"
BRANCH="$(git -C "${STORE}" symbolic-ref --short HEAD)"
echo
if git -C "${CASE_DIR}/.remote/remote.git" rev-parse --verify "${BRANCH}" >/dev/null 2>&1; then
    echo "remote: received store branch OK"
else
    echo "remote: store branch MISSING"
fi
