#!/usr/bin/env bash
# save-no-files.sh – Save (= sync) with no Claude files present.
#
# `clc save` is an alias for `clc sync`. With an empty brain the store sync is a
# noop and the file count is zero; the store tracks only the seeded registry.
#
# Produces in test/playground/save-no-files/:
#   main/  – clean repo with no Claude files
#
# Asserts:
#   1. `clc save` reports zero files synced to the store.
#   2. The store tracks only the registry (no project subtree).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/save-no-files"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

# Pin store-commit dates defensively (the store stamps its own identity, but pin
# dates so any history that leaks is deterministic).
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – save-no-files" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

(cd "${CASE_DIR}/main" && "$BASH" "${CLC}" --no-color save)

# Assert store content deterministically. With CLC_STORE set, the data root is
# CLC_STORE, so the store git repo lives at CLC_STORE/store.
STORE="${CLC_STORE}/store"
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"

echo
echo "store tracked files:"
git -C "${STORE}" ls-files | sed "s|^${PREFIX}/|<project>/|"
