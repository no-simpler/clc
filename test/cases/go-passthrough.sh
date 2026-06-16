#!/usr/bin/env bash
# go-passthrough.sh – Action test: `clc go <name> -- <claude args…>` passes the
# trailing args through to the launched (stubbed) claude binary.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/go-passthrough"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – go-passthrough" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

git worktree add -q "${CASE_DIR}/main/.claude/worktrees/login" -b feature/login

mkdir -p "${CASE_DIR}/.bin"
cat > "${CASE_DIR}/.bin/claude-stub" <<'EOF'
#!/usr/bin/env bash
echo "[claude-stub] cwd=$(pwd)"
echo "[claude-stub] args=$*"
EOF
chmod +x "${CASE_DIR}/.bin/claude-stub"
export CLC_LAUNCH_CMD="${CASE_DIR}/.bin/claude-stub"

cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color go login -- --resume foo
