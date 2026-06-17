#!/usr/bin/env bash
# hook-autosync.sh – End-to-end: real git commits fire the installed clc hooks
# (post-commit → `clc sync --from-hook`) and reconcile the brain into the store.
#
# Produces in test/playground/hook-autosync/:
#   main/                       – enrolled main worktree (hooks installed by enroll)
#   main/.claude/worktrees/feat – managed peer worktree (nested convention path)
#
# Asserts the v3.1 direction-aware hook behavior (all state-based — never snapshots
# raw git-commit stdout/SHAs):
#   1. Main-worktree auto-sync: editing CLAUDE.md + committing in main fires the
#      hook; the store mirror then holds the edited content.
#   2. Peer auto-promote (strictly ahead): editing the brain + committing in a PEER
#      whose brain is ahead of (and uncontested by) the store auto-promotes the edit
#      into BOTH the store and the main worktree, with a stderr notice.
#   3. Peer diverged nudge: once main has moved the brain and the peer edits it
#      differently, the peer commit does NOT promote (store keeps main's content);
#      a 'reconcile' nudge surfaces on the commit's stderr.
#   4. No-op: a non-brain commit in an in-sync worktree fires the hook but yields no
#      store commit.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/hook-autosync"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

# Pin dates so any store-commit history that leaks is deterministic.
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# ── Setup main repo with an initial brain; all setup commits BEFORE enroll. ──
git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – hook-autosync" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# initial instructions" > "${CASE_DIR}/main/CLAUDE.md"

# Enroll: installs hooks + does the first sync of the initial brain.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

STORE="${XDG_DATA_HOME}/clc/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

# ── 1. Main-worktree auto-sync via post-commit hook. ──
cd "${CASE_DIR}/main"
echo "# edited in main" > CLAUDE.md
echo "main change 1" >> README.md
${GIT} commit -q -am "tracked change in main"

echo "1. main auto-sync — store CLAUDE.md after main commit:"
git -C "${STORE}" show "HEAD:${PREFIX}/CLAUDE.md"

# ── 2. Peer auto-promote (strictly ahead, uncontested). ──
# Create a managed peer at the nested convention path via clc go (new branch →
# -y skips the confirm; --no-launch skips the binary launch). go records the peer's
# baseline = store HEAD (brain == main's "# edited in main").
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

cd "${PEER}"
echo "# edited in peer" > CLAUDE.md
echo "peer change 1" >> README.md
${GIT} commit -q -am "tracked change in peer" 2>"${CASE_DIR}/peer-ahead.stderr" || true

echo
echo "2. peer ahead — promotion notice on commit stderr:"
grep -F "→ store + main" "${CASE_DIR}/peer-ahead.stderr" >/dev/null \
    && echo "   promotion notice emitted" || echo "   (no notice found)"
echo "   store CLAUDE.md after peer commit (promoted):"
git -C "${STORE}" show "HEAD:${PREFIX}/CLAUDE.md"
echo "   main CLAUDE.md after peer commit (mirrored into trunk):"
cat "${CASE_DIR}/main/CLAUDE.md"

# ── 3. Peer diverged nudge. ──
# Main moves the brain again (store advances); the peer then edits it differently →
# diverged → no promote, store keeps main's content, a 'reconcile' nudge fires.
cd "${CASE_DIR}/main"
echo "# main v2" > CLAUDE.md
echo "main change 2" >> README.md
${GIT} commit -q -am "second tracked change in main"

cd "${PEER}"
echo "# peer v2" > CLAUDE.md
echo "peer change 2" >> README.md
${GIT} commit -q -am "second tracked change in peer" 2>"${CASE_DIR}/peer-diverged.stderr" || true

echo
echo "3. peer diverged — nudge on commit stderr:"
grep -F "diverged from the store" "${CASE_DIR}/peer-diverged.stderr" >/dev/null \
    && echo "   reconcile nudge emitted" || echo "   (no nudge found)"
echo "   store CLAUDE.md after diverged peer commit (still main's):"
git -C "${STORE}" show "HEAD:${PREFIX}/CLAUDE.md"

# ── 4. No-op: a non-brain commit in an in-sync worktree creates no store commit. ──
STORE_HEAD_BEFORE="$(git -C "${STORE}" rev-list --count HEAD)"
cd "${CASE_DIR}/main"
echo "main change 3 (non-brain)" >> README.md
${GIT} commit -q -am "non-brain change in main" 2>/dev/null
STORE_HEAD_AFTER="$(git -C "${STORE}" rev-list --count HEAD)"

echo
echo "4. no-op — store commit count unchanged after non-brain main commit:"
if [[ "${STORE_HEAD_BEFORE}" == "${STORE_HEAD_AFTER}" ]]; then
    echo "   store unchanged (no spurious commit)"
else
    echo "   store CHANGED: ${STORE_HEAD_BEFORE} -> ${STORE_HEAD_AFTER}"
fi
