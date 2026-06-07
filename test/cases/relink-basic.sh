#!/usr/bin/env bash
# relink-basic.sh – Move handling: re-key a relocated repo (P7, §4.4/§6.4).
#
# Produces in test/playground/relink-basic/:
#   moved/  – the repo after being `mv`d from old/ (carries its own .git)
#
# Flow: enroll old/, `mv old moved`, run `clc relink` from moved/. Auto-detects
# the old path by matching origin + vanished path. Asserts:
#   1. relink reports old → new.
#   2. The registry now keys the NEW HOME-relative path (old gone).
#   3. The store subtree moved (old prefix gone, new present).
#   4. .git/info/exclude still has the patterns; hooks present at the new location.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/relink-basic"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/old"
cd "${CASE_DIR}/old"
git checkout -q -b main
echo "# clc test – relink" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/proj.git
echo "# project instructions" > CLAUDE.md

# Enroll at the old location.
"$BASH" "${CLC}" --no-color enroll > /dev/null

STORE="${XDG_DATA_HOME}/clc/store"
OLD_REL="$(cd "${CASE_DIR}/old" && pwd | sed "s|^${HOME}/||")"

# Move the repo (carries its own .git). The old path no longer exists.
mv "${CASE_DIR}/old" "${CASE_DIR}/moved"
NEW_REL="$(cd "${CASE_DIR}/moved" && pwd | sed "s|^${HOME}/||")"

# Relink from the new location (auto-detect the old path).
(cd "${CASE_DIR}/moved" && "$BASH" "${CLC}" --no-color relink)

echo
echo "registry:"
cat "${STORE}/.clc/registry" | sed "s|${OLD_REL}|<old>|; s|${NEW_REL}|<new>|"

echo
echo "store tracked files:"
git -C "${STORE}" ls-files | sed "s|^${OLD_REL}/|<old>/|; s|^${NEW_REL}/|<new>/|"

echo
echo ".git/info/exclude:"
cat "${CASE_DIR}/moved/.git/info/exclude"

echo
echo "hooks present:"
for h in post-commit post-merge post-checkout; do
    [[ -f "${CASE_DIR}/moved/.git/hooks/${h}" ]] && echo "  ${h}"
done
