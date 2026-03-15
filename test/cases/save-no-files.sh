#!/usr/bin/env bash
# save-no-files.sh – Save with no Claude files present.
#
# Produces in test/playground/save-no-files/:
#   main/  – clean repo with no Claude files

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/save-no-files"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – save-no-files" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

(cd "${CASE_DIR}/main" && bash "${CLC}" --no-color save) \
    | sed -E 's|/[0-9]{10,}$|/<timestamp>|'
