#!/usr/bin/env bash
# store-respects-gitignore.sh – the managed brain respects the project's gitignore.
#
# clc stores the brain (CLAUDE.md any depth + root .claude/) but must DEFER to the
# project's own ignore intent: files matched by an in-repo .gitignore (e.g. a
# dependency's vendor/…/CLAUDE.md) or by the user's global excludes (e.g. the
# per-machine .claude/settings.local.json) are NOT part of the managed brain and
# must stay out of the store. clc's OWN .git/info/exclude patterns (CLAUDE.md,
# /.claude/) are disregarded — otherwise the brain would never be stored.
#
# Asserts: settings.json + root CLAUDE.md are stored; settings.local.json
# (global) and vendor/lib/CLAUDE.md (in-repo .gitignore) are NOT.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/store-respects-gitignore"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# Global excludes (the XDG fallback git consults). run.sh isolates XDG_CONFIG_HOME
# under the playground. Ignore the per-machine settings file.
mkdir -p "${XDG_CONFIG_HOME}/git"
printf '%s\n' '**/.claude/settings.local.json' > "${XDG_CONFIG_HOME}/git/ignore"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – store-respects-gitignore" > README.md
# The project transitively ignores its dependency dir (a real-world pattern).
echo "/vendor/" > .gitignore
git add README.md .gitignore
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

# Real brain (kept).
mkdir -p "${CASE_DIR}/main/.claude"
echo '{}'              > "${CASE_DIR}/main/.claude/settings.json"
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"
# Per-machine settings — globally ignored (dropped).
echo '{"local":true}' > "${CASE_DIR}/main/.claude/settings.local.json"
# A dependency that bundled its own CLAUDE.md inside the gitignored vendor/ (dropped).
mkdir -p "${CASE_DIR}/main/vendor/acme/lib"
echo "# vendored dep brain" > "${CASE_DIR}/main/vendor/acme/lib/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save) >/dev/null

STORE="${CLC_STORE}/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"
echo "store tracked files:"
git -C "${STORE}" ls-files | sed "s|^${PREFIX}/|<project>/|"
