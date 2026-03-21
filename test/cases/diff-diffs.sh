#!/usr/bin/env bash
# diff-diffs.sh – diff when worktree has all three diff categories vs storage.
#
# Produces in test/playground/diff-diffs/:
#   main/  – worktree that diverges from saved state in all three ways

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/diff-diffs"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – diff-diffs" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

# Initial Claude files for save snapshot
mkdir -p "${CASE_DIR}/main/.claude"
echo '{}' > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

# Save silently
(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save) > /dev/null

# Create all three diff categories:
# only_storage: .claude/settings.json (remove from worktree)
rm "${CASE_DIR}/main/.claude/settings.json"
# different: CLAUDE.md (modify content)
echo "# MODIFIED instructions" > "${CASE_DIR}/main/CLAUDE.md"
# only_worktree: docs/CLAUDE.md (new file not in storage)
mkdir -p "${CASE_DIR}/main/docs"
echo "# nested instructions" > "${CASE_DIR}/main/docs/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color diff) \
    | sed -E "s|${CASE_DIR}/\\.clc-store/saved/[^/]+/[0-9]+/|<save>/|g" \
    | sed -E "s|${CASE_DIR}/main/|<wt>/|g" \
    || true
