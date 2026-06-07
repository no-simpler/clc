#!/usr/bin/env bash
# backup-bundle.sh – Backup the central store to a local bundle target (P6).
#
# Produces in test/playground/backup-bundle/:
#   main/  – main worktree with a brain, enrolled into the store
#
# Asserts:
#   1. `clc backup` (force) reports the bundle target pushed.
#   2. The bundle file exists and `git bundle verify` succeeds (deterministic OK).
#   3. A second `clc backup` rotates the previous bundle to .bundle.prev.
#   4. `clc status` shows the Backups staleness section (age deterministic via
#      CLC_NOW: push and status at the same epoch → "just now").
#
# Determinism seams (§6.2): CLC_SYNC_SYNC=1 (synchronous push, no async races),
# CLC_NOW=<fixed> (pins debounce + staleness age). store = XDG_DATA_HOME/clc/store
# (isolated by run.sh); CLC_STORE intentionally unset.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/backup-bundle"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
export CLC_SYNC_SYNC=1
export CLC_NOW=1700000000

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – backup-bundle" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

# Sync the brain into the store (so the store has commits to bundle).
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color sync > /dev/null)

# Configure a bundle target under the playground.
BUNDLE="${CASE_DIR}/store.bundle"
mkdir -p "${XDG_CONFIG_HOME}/clc"
git config -f "${XDG_CONFIG_HOME}/clc/config" clc.backup.local.kind bundle
git config -f "${XDG_CONFIG_HOME}/clc/config" clc.backup.local.path "${BUNDLE}"

# Force a backup (synchronous). Should report pushed.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color backup)

echo
if [[ -f "${BUNDLE}" ]] && git bundle verify "${BUNDLE}" >/dev/null 2>&1; then
    echo "bundle: exists and verifies OK"
else
    echo "bundle: MISSING or INVALID"
fi

# Second backup → rotation: previous bundle becomes .prev.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color backup > /dev/null)
echo
if [[ -f "${BUNDLE}.prev" ]] && git bundle verify "${BUNDLE}.prev" >/dev/null 2>&1; then
    echo "bundle rotation: .prev exists and verifies OK"
else
    echo "bundle rotation: .prev MISSING or INVALID"
fi

# Status shows the Backups section; push + status at the same CLC_NOW → "just now".
echo
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color status)
