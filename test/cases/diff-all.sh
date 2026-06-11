#!/usr/bin/env bash
# diff-all.sh – `clc diff --all`: full Git diff across every enrolled repo.
#
# Three repos enrolled into one (XDG-isolated) store under .repos/ (a dot-dir → not
# discovered as worktrees; asserts ACTION output only). Sorted registry order:
#   clean   – untouched after enroll        → "in sync" one-liner
#   drift   – all three diff categories     → header + git-diff blocks
#   nosync  – enrolled with NO brain files  → "never synced" one-liner
#
# Asserts the per-repo diff blocks (store/worktree paths normalized to <save>/<wt>,
# exactly as diff-diffs does) plus the in-sync / never-synced status lines, and the
# exit-1-on-any-drift contract.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/diff-all"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}/.repos"

enroll_repo() {
    local name="$1" kind="$2"
    local wt="${CASE_DIR}/.repos/${name}"
    git init -q "${wt}"
    ( cd "${wt}"
      git checkout -q -b main
      echo "# ${name}" > README.md
      git add README.md
      ${GIT} commit -q -m "Initial commit"
      if [[ "${kind}" == "brain" ]]; then
          mkdir -p .claude
          echo '{}' > .claude/settings.json
          echo "# ${name} instructions" > CLAUDE.md
      fi
      "$BASH" "${CLC}" --no-color enroll > /dev/null )
}

enroll_repo clean  brain
enroll_repo drift  brain
enroll_repo nosync none

# Give 'drift' all three diff categories vs the store (no commit → no hook fires):
DRIFT="${CASE_DIR}/.repos/drift"
rm "${DRIFT}/.claude/settings.json"                 # only_storage
echo "# MODIFIED instructions" > "${DRIFT}/CLAUDE.md"  # different
mkdir -p "${DRIFT}/docs"
echo "# nested instructions" > "${DRIFT}/docs/CLAUDE.md"  # only_worktree

# diff prints git-diff paths for each repo's store mirror (a<save>) and worktree
# (b<wt>). Only 'drift' produces diff bodies; normalize its two absolute paths.
STORE="${XDG_DATA_HOME}/clc/store"
DRIFT_REL="${DRIFT#${HOME}/}"
SAVE_DIR="${STORE}/${DRIFT_REL}"
set +e
(cd "${CASE_DIR}" && "$BASH" "${CLC}" --no-color diff --all) \
    | sed -E "s|${SAVE_DIR}/|<save>/|g" \
    | sed -E "s|${DRIFT}/|<wt>/|g"
rc=${PIPESTATUS[0]}
set -e
echo
echo "exit: ${rc}"
