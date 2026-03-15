#!/usr/bin/env bash
# ls-tracked.sh – Some Claude files are git-managed; clc ls warns about them.
#
# Produces in test/playground/ls-tracked/:
#   main/  – main worktree with:
#              CLAUDE.md at root: committed (tracked) → git-managed → warning
#              docs/CLAUDE.md: staged but not committed → git-managed → warning
#              .claude/ at root: properly ignored → no warning

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/ls-tracked"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – ls-tracked" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

# Properly ignore .claude/ only (CLAUDE.md not ignored → visible to git if present)
echo "/.claude/" >> .git/info/exclude

# Commit CLAUDE.md at root (force-add, bad state)
echo "# project instructions" > CLAUDE.md
git add -f CLAUDE.md
${GIT} commit -q -m "Add CLAUDE.md (bad state)"

# Stage a nested CLAUDE.md (force-add, not yet committed)
mkdir -p docs
echo "# nested instructions" > docs/CLAUDE.md
git add -f docs/CLAUDE.md

# Create .claude/ directory (properly ignored)
mkdir -p .claude
echo "{}" > .claude/settings.json

(cd "${CASE_DIR}/main" && bash "${CLC}" --no-color ls)
