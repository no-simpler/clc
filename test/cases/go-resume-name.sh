#!/usr/bin/env bash
# go-resume-name.sh – Action test: `clc go <name>` resumes an EXISTING managed
# worktree by its exact name, then launches the (stubbed) claude binary in it.
#
# CLC_LAUNCH_CMD points at a stub (.bin/claude-stub, in a dot-dir so the runner's
# */ glob skips it) that echoes its cwd + args; the runner normalizes the cwd to
# %%PARENT_DIR_ABS%%/… so the launch line is deterministic.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/go-resume-name"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – go-resume-name" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# Locally ignore Claude files so the nested .claude/worktrees/ dir does not make
# main show spurious (dirty) / "Claude files detected".
"$BASH" "${CLC}" --no-color ignore > /dev/null

# Existing managed worktree.
git worktree add -q "${CASE_DIR}/main/.claude/worktrees/login" -b feature/login

# Claude launch stub (dot-dir → not discovered as a worktree).
mkdir -p "${CASE_DIR}/.bin"
cat > "${CASE_DIR}/.bin/claude-stub" <<'EOF'
#!/usr/bin/env bash
echo "[claude-stub] cwd=$(pwd)"
echo "[claude-stub] args=$*"
EOF
chmod +x "${CASE_DIR}/.bin/claude-stub"
export CLC_LAUNCH_CMD="${CASE_DIR}/.bin/claude-stub"

cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color go login
