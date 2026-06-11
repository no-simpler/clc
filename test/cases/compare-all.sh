#!/usr/bin/env bash
# compare-all.sh – `clc compare --all`: audit every enrolled repo against the store.
#
# Four repos enrolled into one (XDG-isolated) store under .repos/ (a dot-dir → not
# discovered as worktrees; this case asserts ACTION output only). Sorted registry
# order makes the per-repo audit deterministic:
#   clean   – untouched after enroll        → in sync
#   drift   – brain modified after enroll   → drifted (N)
#   gone    – enrolled, worktree removed    → missing
#   nosync  – enrolled with NO brain files  → never synced
#
# Asserts the one-line-per-repo audit AND the exit-1-on-any-drift contract.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/compare-all"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}/.repos"

# Enroll a repo; second arg "brain" gives it CLAUDE.md + .claude, "none" leaves it
# brain-less (→ nothing in the store → "never synced"). Commits precede enroll so
# the post-commit hook never fires mid-test.
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
enroll_repo gone   brain

# Diverge 'drift' (no commit → no hook); remove 'gone' entirely.
echo "# drift CHANGED" > "${CASE_DIR}/.repos/drift/CLAUDE.md"
rm -rf "${CASE_DIR}/.repos/gone"

# Audit every enrolled repo and capture the exit code (1 expected: drift present).
set +e
(cd "${CASE_DIR}" && "$BASH" "${CLC}" --no-color compare --all)
rc=$?
set -e
echo
echo "exit: ${rc}"
