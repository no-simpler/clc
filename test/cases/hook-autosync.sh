#!/usr/bin/env bash
# hook-autosync.sh – End-to-end: real git commits fire the installed clc hooks
# (post-commit → `clc sync --from-hook`) and auto-sync the brain into the store.
#
# Produces in test/playground/hook-autosync/:
#   main/                       – enrolled main worktree (hooks installed by enroll)
#   main/.claude/worktrees/feat – managed peer worktree (nested convention path)
#
# Asserts (all state-based — never snapshots raw git-commit stdout/SHAs):
#   1. Main-worktree auto-sync: editing CLAUDE.md + committing in main fires the
#      hook; the store mirror then holds the edited content.
#   2. Canonical-main policy: editing the brain + committing in a PEER fires the
#      hook, but the store keeps mirroring MAIN (a peer can never clobber the
#      canonical brain). The peer's divergence is surfaced as a stderr nudge.
#   3. No-op: a non-brain commit in the peer fires the hook but yields no store
#      commit (main's brain is unchanged).
#   4. Deliberate promotion: `clc save` from the peer is the explicit
#      worktree→store path; the store then reflects the peer's brain.

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
# The brain is gitignored (by enroll), so it is never part of a commit. Edit the
# brain, then make an ordinary tracked commit — that commit fires the post-commit
# hook → clc sync --from-hook → the (untracked, edited) brain is synced.
cd "${CASE_DIR}/main"
echo "# edited in main" > CLAUDE.md
echo "main change 1" >> README.md
${GIT} commit -q -am "tracked change in main"

echo "1. main auto-sync — store CLAUDE.md after main commit:"
git -C "${STORE}" show "HEAD:${PREFIX}/CLAUDE.md"

# ── 2. Canonical-main policy + peer-divergence nudge. ──
# Create a managed peer at the nested convention path via clc go (new branch →
# -y skips the confirm prompt; --no-launch skips the binary launch).
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

cd "${PEER}"
echo "# edited in peer" > CLAUDE.md
echo "peer change 1" >> README.md
# Capture the commit's stderr; the hook's peer-divergence nudge surfaces there.
${GIT} commit -q -am "tracked change in peer" 2>"${CASE_DIR}/peer-commit.stderr" || true

echo
echo "2. peer commit — divergence nudge on commit stderr:"
grep -F "brain differs from the store" "${CASE_DIR}/peer-commit.stderr" >/dev/null \
    && echo "   nudge emitted" || echo "   (no nudge found)"
echo "   store CLAUDE.md after peer commit (still canonical = main):"
git -C "${STORE}" show "HEAD:${PREFIX}/CLAUDE.md"

# ── 3. No-op: a non-brain commit in the peer must not create a store commit. ──
# The hook syncs MAIN (unchanged since step 1), so the store is a no-op regardless
# of the peer's diverging brain.
STORE_HEAD_BEFORE="$(git -C "${STORE}" rev-list --count HEAD)"
cd "${PEER}"
echo "peer change 2 (non-brain)" >> README.md
${GIT} commit -q -am "non-brain change in peer" 2>/dev/null
STORE_HEAD_AFTER="$(git -C "${STORE}" rev-list --count HEAD)"

echo
echo "3. no-op — store commit count unchanged after non-brain commit:"
if [[ "${STORE_HEAD_BEFORE}" == "${STORE_HEAD_AFTER}" ]]; then
    echo "   store unchanged (no spurious commit)"
else
    echo "   store CHANGED: ${STORE_HEAD_BEFORE} -> ${STORE_HEAD_AFTER}"
fi

# ── 4. Deliberate promotion: `clc save` from the peer pushes ITS brain. ──
cd "${PEER}"
(cd "${PEER}" && "$BASH" "${CLC}" --no-color save) > /dev/null 2>&1

echo
echo "4. deliberate promotion — store CLAUDE.md after 'clc save' in peer:"
git -C "${STORE}" show "HEAD:${PREFIX}/CLAUDE.md"
