#!/usr/bin/env bash
# doctor-basic.sh – Read-only cross-machine health check (P7).
#
# Produces in test/playground/doctor-basic/:
#   ok/      – an enrolled repo present with a matching origin   → "ok"
#   drift/   – an enrolled repo present with a different origin   → "origin drift"
#   (gone/ is registered but never created on disk)              → "missing"
#
# Asserts `clc doctor` reports ok / origin drift / missing per entry. Read-only:
# never clones, moves, or writes into any repo. Output is content-derived
# (HOME-relative paths normalize to %%PARENT_DIR_HOME%%; origins are fixed).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/doctor-basic"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

# Helper: make a repo with a brain and a given origin, then enroll it.
make_repo() {
    local dir="$1" origin="$2"
    git init -q "${dir}"
    ( cd "${dir}"
      git checkout -q -b main
      echo "# clc test" > README.md
      git add README.md
      ${GIT} commit -q -m "Initial commit"
      git remote add origin "${origin}"
      echo "# project instructions" > CLAUDE.md
      "$BASH" "${CLC}" --no-color enroll > /dev/null )
}

# ok/: present, origin matches the registry.
make_repo "${CASE_DIR}/ok" "git@example.com:me/ok.git"

# drift/: enroll with one origin, then change the local origin so it mismatches
# the registry (the registry keeps the enroll-time origin).
make_repo "${CASE_DIR}/drift" "git@example.com:me/drift.git"
( cd "${CASE_DIR}/drift" && git remote set-url origin git@example.com:me/MOVED.git )

# gone/: register a repo whose local path does not exist on disk. Write the
# registry line directly (the working-tree registry is what doctor reads).
STORE="${XDG_DATA_HOME}/clc/store"
GONE_REL="$( (cd "${CASE_DIR}" && pwd) | sed "s|^${HOME}/||" )/gone"
printf '%s\t%s\n' "${GONE_REL}" "git@example.com:me/gone.git" >> "${STORE}/.clc/registry"
LC_ALL=C sort -o "${STORE}/.clc/registry" "${STORE}/.clc/registry"

# Read-only doctor from one of the present repos (also exercises the in-repo
# "unregistered" check, which is silent here since both repos are registered).
(cd "${CASE_DIR}/ok" && "$BASH" "${CLC}" --no-color doctor)
