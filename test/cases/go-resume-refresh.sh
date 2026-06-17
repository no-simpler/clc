#!/usr/bin/env bash
# go-resume-refresh.sh – `clc go <name>` resuming a worktree that is purely behind
# the store (a safe fast-forward) auto-refreshes its brain with a one-line notice,
# then launches the (stubbed) claude binary.
#
# Produces in test/playground/go-resume-refresh/:
#   main/                       – enrolled main worktree
#   main/.claude/worktrees/feat – managed peer, spawned then left behind the store
#
# Asserts the resume output carries "refreshed N brain file(s) from store" and the
# refreshed file is present in the peer before launch.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/go-resume-refresh"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – go-resume-refresh" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

mkdir -p "${CASE_DIR}/main/.claude"
echo "# instructions" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

# Spawn the peer (baseline = store at spawn time).
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
PEER="${CASE_DIR}/main/.claude/worktrees/feat"

# Advance the store via a main commit: add a new brain file the peer lacks → the
# peer is now purely behind.
cd "${CASE_DIR}/main"
echo "# more" > .claude/extra.md
echo "main change" >> README.md
${GIT} commit -q -am "add a brain file in main"

# Launch stub (dot-dir → not discovered as a worktree).
mkdir -p "${CASE_DIR}/.bin"
cat > "${CASE_DIR}/.bin/claude-stub" <<'EOF'
#!/usr/bin/env bash
echo "[claude-stub] launched in $(basename "$(pwd)")"
EOF
chmod +x "${CASE_DIR}/.bin/claude-stub"
export CLC_LAUNCH_CMD="${CASE_DIR}/.bin/claude-stub"

cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color go feat

echo
echo "peer has refreshed file? $([[ -f "${PEER}/.claude/extra.md" ]] && echo yes || echo no)"
