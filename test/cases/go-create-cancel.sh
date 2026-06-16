#!/usr/bin/env bash
# go-create-cancel.sh – Action test: `clc go <new-branch> --no-launch` with no
# stdin (EOF) cancels safely. A brand-new branch prompts for confirmation; an
# empty/EOF answer prints "Cancelled." and exits 0 without creating anything.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/go-create-cancel"
CLC="${REPO_ROOT}/clc.sh"
GIT="git -c user.email=clc@test -c user.name=clc-test -c commit.gpgsign=false"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

git init -q "${CASE_DIR}/main"
cd "${CASE_DIR}/main"
git checkout -q -b main
echo "# clc test – go-create-cancel" > README.md
git add README.md
${GIT} commit -q -m "Initial commit"

"$BASH" "${CLC}" --no-color ignore > /dev/null

cd "${CASE_DIR}/main"
# New branch → prompt; EOF answer cancels.
"$BASH" "${CLC}" --no-color go spike --no-launch </dev/null
