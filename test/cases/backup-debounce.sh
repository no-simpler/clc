#!/usr/bin/env bash
# backup-debounce.sh – Debounce gates sync-triggered backups; force overrides (P6).
#
# Produces in test/playground/backup-debounce/:
#   main/  – main worktree with a brain, enrolled (hooks not exercised here)
#
# Flow (all deterministic via CLC_NOW; CLC_SYNC_SYNC=1 makes the sync-triggered
# push synchronous so its effect is observable in-process):
#   1. At CLC_NOW=T: `clc backup` (force) writes the target stamp = T.
#   2. At CLC_NOW=T+10 with interval=900: a `clc sync` that actually changes the
#      brain triggers a debounced backup → SKIPPED (stamp stays T).
#   3. At CLC_NOW=T+10: `clc backup` (force) overrides the debounce → stamp = T+10.
#
# Asserts the stamp value at each step (deterministic; no SHAs/dates/abs-paths).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/backup-debounce"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
export CLC_SYNC_SYNC=1

T=1700000000

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – backup-debounce" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

echo "# v1" > "${CASE_DIR}/main/CLAUDE.md"
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color sync > /dev/null)

BUNDLE="${CASE_DIR}/store.bundle"
mkdir -p "${XDG_CONFIG_HOME}/clc"
git config -f "${XDG_CONFIG_HOME}/clc/config" clc.backup.local.kind bundle
git config -f "${XDG_CONFIG_HOME}/clc/config" clc.backup.local.path "${BUNDLE}"
# interval default is 900s; make it explicit for clarity.
git config -f "${XDG_CONFIG_HOME}/clc/config" clc.backup.interval 900

STAMP="${XDG_STATE_HOME}/clc/backup/local.stamp"

# Step 1: force a backup at T → stamp = T.
(cd "${CASE_DIR}/main" && CLC_NOW="${T}" "$BASH" "${CLC}" --no-color backup > /dev/null)
echo "stamp after force backup at T: $(($(cat "${STAMP}") - T)) (relative to T)"

# Step 2: change the brain and sync at T+10. The sync triggers a debounced
# backup; interval 900 > 10 → SKIPPED, stamp unchanged.
echo "# v2" > "${CASE_DIR}/main/CLAUDE.md"
(cd "${CASE_DIR}/main" && CLC_NOW="$((T + 10))" "$BASH" "${CLC}" --no-color sync > /dev/null)
echo "stamp after debounced sync at T+10: $(($(cat "${STAMP}") - T)) (relative to T)"

# Step 3: force a backup at T+10 → overrides debounce, stamp = T+10.
(cd "${CASE_DIR}/main" && CLC_NOW="$((T + 10))" "$BASH" "${CLC}" --no-color backup > /dev/null)
echo "stamp after force backup at T+10: $(($(cat "${STAMP}") - T)) (relative to T)"
