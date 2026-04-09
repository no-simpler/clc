#!/usr/bin/env bash
# submodule.sh – Verify that submodules are treated as individual repos.
#
# Produces in test/playground/submodule/:
#   parent/   – parent repo containing a submodule
#   sub-repo/ – bare repo used as the submodule origin
#
# Tests:
#   1. clc save from submodule saves to submodule-specific storage (not parent)
#   2. clc save from parent excludes submodule CLAUDE.md files
#   3. clc ls  from parent excludes submodule CLAUDE.md files

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/submodule"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# ── Create a bare repo to serve as the submodule origin ──────────────────────

# Use a subdirectory for the bare repo so the test runner doesn't try to
# run clc in it (the runner iterates top-level dirs only).
mkdir -p "${CASE_DIR}/.repos"
git init -q --bare "${CASE_DIR}/.repos/sub-repo.git"

# Bootstrap it with a commit so it can be added as a submodule
tmp_clone="${CASE_DIR}/_tmp_sub"
git clone -q "${CASE_DIR}/.repos/sub-repo.git" "${tmp_clone}" 2>/dev/null
cd "${tmp_clone}"
git checkout -q -b main
echo "# sub" > README.md
git add README.md
${GIT} commit -q -m "Initial sub commit"
git push -q origin main
cd "${CASE_DIR}"
rm -rf "${tmp_clone}"

# ── Create the parent repo ──────────────────────────────────────────────────

git init -q "${CASE_DIR}/parent"
cd "${CASE_DIR}/parent"
git checkout -q -b main
echo "# parent" > README.md
git add README.md
${GIT} commit -q -m "Initial parent commit"

# Add the submodule
git -c protocol.file.allow=always submodule add -q -b main "${CASE_DIR}/.repos/sub-repo.git" sub
${GIT} commit -q -m "Add submodule"

# ── Set up Claude files ─────────────────────────────────────────────────────

# Ignore Claude files in parent
"$BASH" "${CLC}" --no-color ignore > /dev/null

# Ignore Claude files in submodule
(cd "${CASE_DIR}/parent/sub" && "$BASH" "${CLC}" --no-color ignore > /dev/null)

# Parent Claude files
echo "# parent instructions" > "${CASE_DIR}/parent/CLAUDE.md"
mkdir -p "${CASE_DIR}/parent/docs"
echo "# parent docs" > "${CASE_DIR}/parent/docs/CLAUDE.md"

# Submodule Claude files
echo "# sub instructions" > "${CASE_DIR}/parent/sub/CLAUDE.md"

# ── Action: save from submodule, then save from parent, then ls both ────────

echo "=== save from submodule ==="
(cd "${CASE_DIR}/parent/sub" && "$BASH" "${CLC}" --no-color save) \
    | sed -E 's|/[0-9]{10,}$|/<timestamp>|'

echo ""
echo "=== save from parent ==="
(cd "${CASE_DIR}/parent" && "$BASH" "${CLC}" --no-color save) \
    | sed -E 's|/[0-9]{10,}$|/<timestamp>|'

echo ""
echo "=== ls from submodule ==="
(cd "${CASE_DIR}/parent/sub" && "$BASH" "${CLC}" --no-color ls)

echo ""
echo "=== ls from parent ==="
(cd "${CASE_DIR}/parent" && "$BASH" "${CLC}" --no-color ls)
