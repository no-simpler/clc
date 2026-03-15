#!/usr/bin/env bash
# ls-ignored.sh – Claude files exist but are properly ignored; clc ls shows them normally.
#
# Produces in test/playground/ls-ignored/:
#   main/  – main worktree with:
#              .claude/ at root (ignored via exclude)
#              CLAUDE.md at root (ignored via exclude)
#              docs/CLAUDE.md nested (ignored via exclude)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/ls-ignored"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – ls-ignored" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# Properly ignore Claude patterns
bash "${CLC}" --no-color ignore > /dev/null

# Create Claude files (all ignored, so not visible to git)
mkdir -p "${CASE_DIR}/main/.claude"
echo "{}" > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"
mkdir -p "${CASE_DIR}/main/docs"
echo "# nested instructions" > "${CASE_DIR}/main/docs/CLAUDE.md"

(cd "${CASE_DIR}/main" && bash "${CLC}" --no-color ls)
