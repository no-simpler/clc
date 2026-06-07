#!/usr/bin/env bash
# adopt-basic.sh – Adopt-only cold-start: deploy into present repos (P7, §6.4).
#
# Produces in test/playground/adopt-basic/:
#   here/  – a present repo matching a registry entry → adopt (deploy, no clone)
#   (gone/ is registered but absent on disk → "missing", never cloned)
#
# Flow: seed the store (enroll here/), then strip here/'s deployed brain + hooks
# + ignore so adopt has work to do; register a second entry (gone/) with no repo
# on disk. `clc adopt` must redeploy here/'s brain + ignore + hooks and report
# gone/ missing — never cloning anything. Asserts via file existence/content.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/adopt-basic"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/here"
cd "${CASE_DIR}/here"
git checkout -q -b main
echo "# clc test – adopt" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"
git remote add origin git@example.com:me/here.git
echo "# project instructions" > CLAUDE.md

# Enroll to seed the store (brain in the mirror, registry entry).
"$BASH" "${CLC}" --no-color enroll > /dev/null

STORE="${XDG_DATA_HOME}/clc/store"
HERE_REL="$(cd "${CASE_DIR}/here" && pwd | sed "s|^${HOME}/||")"

# Simulate a fresh checkout: drop the deployed brain, ignore patterns, and hooks
# so adopt has something to do.
rm -f "${CASE_DIR}/here/CLAUDE.md"
rm -f "${CASE_DIR}/here/.git/info/exclude"
rm -f "${CASE_DIR}/here/.git/hooks/post-commit" \
      "${CASE_DIR}/here/.git/hooks/post-merge" \
      "${CASE_DIR}/here/.git/hooks/post-checkout"

# Register a second project whose local path does not exist on disk.
GONE_REL="$( (cd "${CASE_DIR}" && pwd) | sed "s|^${HOME}/||" )/gone"
printf '%s\t%s\n' "${GONE_REL}" "git@example.com:me/gone.git" >> "${STORE}/.clc/registry"
LC_ALL=C sort -o "${STORE}/.clc/registry" "${STORE}/.clc/registry"

# Adopt (never clones).
(cd "${CASE_DIR}" && "$BASH" "${CLC}" --no-color adopt) \
    | sed "s|${HERE_REL}|<here>|; s|${GONE_REL}|<gone>|"

echo
echo "here brain redeployed: $([[ -f "${CASE_DIR}/here/CLAUDE.md" ]] && cat "${CASE_DIR}/here/CLAUDE.md")"
echo "here exclude has CLAUDE.md: $(grep -qxF 'CLAUDE.md' "${CASE_DIR}/here/.git/info/exclude" && echo yes || echo no)"
echo "here post-commit hook: $([[ -f "${CASE_DIR}/here/.git/hooks/post-commit" ]] && echo present || echo absent)"
echo "gone/ not created: $([[ -e "${CASE_DIR}/gone" ]] && echo CREATED || echo absent)"
