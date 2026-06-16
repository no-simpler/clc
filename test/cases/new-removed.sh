#!/usr/bin/env bash
# new-removed.sh – Action test: `clc new` was removed in v3; it now errors and
# points the user at `clc go`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/new-removed"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – new-removed" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

cd "${CASE_DIR}/main"
"$BASH" "${CLC}" --no-color new foo 2>&1 || true
