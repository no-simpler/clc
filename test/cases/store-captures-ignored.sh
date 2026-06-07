#!/usr/bin/env bash
# store-captures-ignored.sh – the store mirrors the FULL brain even when a brain
# file is globally gitignored.
#
# Regression: the store's `git add` must not honor the user's global excludes
# (core.excludesfile / the XDG ~/.config/git/ignore fallback). Otherwise a
# globally-ignored brain file such as .claude/settings.local.json is silently
# dropped from the store/backup (v1's plain `cp` captured it; v2 must too).
#
# Asserts the store tracks settings.local.json even though a global ignore matches it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/store-captures-ignored"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# A global gitignore (the XDG fallback git consults) that ignores the local
# settings file. run.sh isolates XDG_CONFIG_HOME under the playground.
mkdir -p "${XDG_CONFIG_HOME}/git"
printf '%s\n' '**/.claude/settings.local.json' > "${XDG_CONFIG_HOME}/git/ignore"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – store-captures-ignored" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

mkdir -p "${CASE_DIR}/main/.claude"
echo '{}'              > "${CASE_DIR}/main/.claude/settings.json"
echo '{"local":true}' > "${CASE_DIR}/main/.claude/settings.local.json"   # globally ignored
echo "# project instructions" > "${CASE_DIR}/main/CLAUDE.md"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save) >/dev/null

# The globally-ignored settings.local.json must be present in the store.
STORE="${CLC_STORE}/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"
echo "store tracked files:"
git -C "${STORE}" ls-files | sed "s|^${PREFIX}/|<project>/|"
