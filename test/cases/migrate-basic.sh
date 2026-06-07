#!/usr/bin/env bash
# migrate-basic.sh – One-shot v1→v2 migration (§7, P8).
#
# Produces in test/playground/migrate-basic/:
#   proj/  – an ignored-but-unenrolled repo with a brain (the v1 state)
#
# Flow: set up a repo with a brain and the v1 local-gitignore signal (clc ignore)
# but DO NOT enroll it. Fabricate a legacy v1 storage entry — a
# ${CLC_STORE}/saved/proj@<md5>/full-path.txt recording the repo's absolute path
# (the md5 is arbitrary; migrate keys off full-path.txt). `clc migrate` discovers
# the repo via full-path.txt, verifies it via the local-gitignore signal, and
# enrolls it. A second `clc migrate` is a no-op ("already enrolled").
#
# Asserts:
#   1. migrate reports the project migrated (HOME-relative path, file count).
#   2. The project is now in the registry (subtree prefix stripped).
#   3. The store mirror holds the brain (two files).
#   4. The post-commit hook is installed.
#   5. .git/info/exclude still carries the two CLC patterns.
#   6. A re-run of migrate reports "already enrolled" (idempotent).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/migrate-basic"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

# Pin store-commit dates so any leaked history is deterministic.
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

# Storage isolation: the legacy saved/ store and the v2 store both live under this
# override root (saved/ and store/ respectively).
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/proj"
cd "${CASE_DIR}/proj"
git checkout -q -b main
echo "# clc test – migrate-basic" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git

mkdir -p "${CASE_DIR}/proj/.claude"
echo '{}' > "${CASE_DIR}/proj/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/proj/CLAUDE.md"

# v1 state: local-gitignore the brain (the discovery signal), but DO NOT enroll.
(cd "${CASE_DIR}/proj" && "$BASH" "${CLC}" --no-color ignore > /dev/null)

# Fabricate a legacy v1 storage entry. The md5 portion is arbitrary hex; migrate
# keys off full-path.txt, not the md5.
PROJ_ABS="$(cd "${CASE_DIR}/proj" && pwd)"
mkdir -p "${CLC_STORE}/saved/proj@0123456789abcdef0123456789abcdef"
printf '%s\n' "${PROJ_ABS}" > "${CLC_STORE}/saved/proj@0123456789abcdef0123456789abcdef/full-path.txt"

# Migrate (action output).
(cd "${CASE_DIR}" && "$BASH" "${CLC}" --no-color migrate)

# Resolve the v2 store + identity the same way clc does.
STORE="${CLC_STORE}/store"
PREFIX="${PROJ_ABS#${HOME}/}"

echo
echo "registry:"
cat "${STORE}/.clc/registry"

echo
echo "store tracked files:"
git -C "${STORE}" ls-files | sed "s|^${PREFIX}/|<project>/|"

echo
echo "post-commit hook: $([[ -f "${CASE_DIR}/proj/.git/hooks/post-commit" ]] && echo present || echo absent)"
echo "exclude has CLAUDE.md: $(grep -qxF 'CLAUDE.md' "${CASE_DIR}/proj/.git/info/exclude" && echo yes || echo no)"
echo "exclude has /.claude/: $(grep -qxF '/.claude/' "${CASE_DIR}/proj/.git/info/exclude" && echo yes || echo no)"

echo
echo "re-run migrate (idempotent):"
(cd "${CASE_DIR}" && "$BASH" "${CLC}" --no-color migrate)
