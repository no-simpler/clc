#!/usr/bin/env bash
# go-resume-seed.sh – `clc go <name>` resuming a baseline-less worktree that is
# fully in sync with the store self-heals: it records a baseline (= store HEAD) so
# later edits classify directionally. Models a worktree created outside clc (older
# clc, or `claude --worktree`) whose brain still matches the store.
#
# Asserts the baseline file is absent before the resume and present after.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/go-resume-seed"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – go-resume-seed" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

mkdir -p "${CASE_DIR}/main/.claude"
echo "# instructions" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color enroll) > /dev/null

# Spawn the peer (in sync with the store), then drop its baseline to mimic a
# worktree clc did not create.
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color go feat -y --no-launch) > /dev/null 2>&1
BASELINE="${CASE_DIR}/main/.git/worktrees/feat/clc-brain-baseline"
rm -f "${BASELINE}"

echo "baseline before resume? $([[ -f "${BASELINE}" ]] && echo yes || echo no)"

# Launch stub (dot-dir → not discovered as a worktree).
mkdir -p "${CASE_DIR}/.bin"
cat > "${CASE_DIR}/.bin/claude-stub" <<'EOF'
#!/usr/bin/env bash
echo "[claude-stub] launched in $(basename "$(pwd)")"
EOF
chmod +x "${CASE_DIR}/.bin/claude-stub"
export CLC_LAUNCH_CMD="${CASE_DIR}/.bin/claude-stub"

cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color go feat > /dev/null

echo "baseline after resume?  $([[ -f "${BASELINE}" ]] && echo yes || echo no)"
