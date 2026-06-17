#!/usr/bin/env bash
# reconcile-infer.sh – Action test: a baseline-less worktree (legacy, or made by
# `claude --worktree`) infers direction from the trunk. A file whose store copy
# still equals main's (uncontested) is shown AHEAD; a file where store != main is
# kept DIVERGED. Reproduces the field report where a purely worktree-forward brain
# was mislabelled "diverged" for lack of a baseline.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/reconcile-infer"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – reconcile-infer" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

# Peer created with a brain (matches the store), then we simulate a worktree clc did
# not create: drop its baseline so classification falls back to inference.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"
rm -f "${CASE_DIR}/main/.git/worktrees/feat/clc-brain-baseline"

# Peer moves CLAUDE.md forward; the store still equals main → uncontested → AHEAD.
echo "# peer edit" > "${PEER}/CLAUDE.md"

# settings.json is edited in BOTH main (uncommitted, so the store keeps the old copy)
# and the peer → store != main → genuinely contested → DIVERGED.
echo '{"main":1}' > "${CASE_DIR}/main/.claude/settings.json"
echo '{"peer":2}' > "${PEER}/.claude/settings.json"

echo "reconcile from the baseline-less peer (CLAUDE.md → inferred ahead; settings.json → diverged):"
(cd "${PEER}" && "$BASH" "${CLC}" --no-color reconcile)
