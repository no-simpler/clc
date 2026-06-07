#!/usr/bin/env bash
# clone-coldstart.sh – Guarded cold-start: clone registered repos (P7, §6.4).
#
# Produces in test/playground/clone-coldstart/:
#   .origins/proj.git  – bare origin for the registered repo (dot-dir so the
#                        runner's */ worktree glob skips it)
#   .origins/other.git – bare origin for the "wrong dir" branch
#   proj/              – cloned by `clc clone` from the bare origin (absent before)
#   wrong/             – a pre-existing unrelated git repo → skip+warn (NOT clobbered)
#
# Flow: seed the store so its registry points proj→origin with the brain in the
# mirror, then remove proj/ on disk. `clc clone` must clone it back, deploy the
# brain, ignore it, and install hooks. A second registered entry (wrong/) already
# exists as a DIFFERENT repo → skip+warn, never clobbered.
#
# Asserts via file existence/content (no SHAs/git output in the snapshot).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/clone-coldstart"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}/.origins"

PROJ_ORIGIN="${CASE_DIR}/.origins/proj.git"
OTHER_ORIGIN="${CASE_DIR}/.origins/other.git"

# ── Bare origin for proj/, populated with a brain. ──────────────────────────────
git init -q "${CASE_DIR}/seed"
( cd "${CASE_DIR}/seed"
  git checkout -q -b main
  echo "# clc test – clone proj" > README.md
  git add README.md
  ${GIT} commit -q -m "Initial commit"
  echo "# project instructions" > CLAUDE.md )
git init -q --bare "${PROJ_ORIGIN}"
git -C "${PROJ_ORIGIN}" symbolic-ref HEAD refs/heads/main
( cd "${CASE_DIR}/seed" && git remote add origin "${PROJ_ORIGIN}" \
    && git push -q origin main )

# Enroll proj/ (a clone of the origin) to seed the store with proj's brain +
# registry entry, then remove proj/ from disk so clone must restore it.
git clone -q "${PROJ_ORIGIN}" "${CASE_DIR}/proj"
( cd "${CASE_DIR}/proj"
  echo "# project instructions" > CLAUDE.md
  "$BASH" "${CLC}" --no-color enroll > /dev/null )
PROJ_REL="$(cd "${CASE_DIR}/proj" && pwd | sed "s|^${HOME}/||")"
rm -rf "${CASE_DIR}/proj" "${CASE_DIR}/seed"

# ── A "wrong" pre-existing repo at a registered path (different origin). ─────────
git init -q --bare "${OTHER_ORIGIN}"
git init -q "${CASE_DIR}/wrong"
( cd "${CASE_DIR}/wrong"
  git checkout -q -b main
  echo "DO NOT CLOBBER" > KEEP.txt
  git add KEEP.txt
  ${GIT} commit -q -m "pre-existing"
  git remote add origin git@example.com:me/SOMETHING-ELSE.git )
WRONG_REL="$(cd "${CASE_DIR}/wrong" && pwd | sed "s|^${HOME}/||")"
# Register wrong/ pointing at the proj origin (so its origin mismatches → skip).
STORE="${XDG_DATA_HOME}/clc/store"
printf '%s\t%s\n' "${WRONG_REL}" "${PROJ_ORIGIN}" >> "${STORE}/.clc/registry"
LC_ALL=C sort -o "${STORE}/.clc/registry" "${STORE}/.clc/registry"

# ── Cold-start clone. ───────────────────────────────────────────────────────────
(cd "${CASE_DIR}" && "$BASH" "${CLC}" --no-color clone) \
    | sed "s|${PROJ_REL}|<proj>|; s|${WRONG_REL}|<wrong>|"

echo
echo "proj brain deployed: $([[ -f "${CASE_DIR}/proj/CLAUDE.md" ]] && cat "${CASE_DIR}/proj/CLAUDE.md")"
echo "proj exclude has CLAUDE.md: $(grep -qxF 'CLAUDE.md' "${CASE_DIR}/proj/.git/info/exclude" && echo yes || echo no)"
echo "proj post-commit hook: $([[ -f "${CASE_DIR}/proj/.git/hooks/post-commit" ]] && echo present || echo absent)"
echo "wrong/ untouched: $(cat "${CASE_DIR}/wrong/KEEP.txt")"
echo "wrong/ no brain: $([[ -f "${CASE_DIR}/wrong/CLAUDE.md" ]] && echo BRAIN-LEAKED || echo clean)"
