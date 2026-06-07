#!/usr/bin/env bash
# migrate-empty.sh – `clc migrate` with no legacy v1 storage (§7, P8).
#
# Produces nothing under test/playground/migrate-empty/ (no worktree). Asserts
# that migrate reports the "no legacy clc storage found" path cleanly when the
# legacy saved/ dir is absent.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/migrate-empty"
CLC="${REPO_ROOT}/clc.sh"

# Storage isolation: point the override root at an empty dir (no saved/ inside).
export CLC_STORE="${CASE_DIR}/.clc-store"

rm -rf "${CASE_DIR}"
mkdir -p "${CASE_DIR}"

"$BASH" "${CLC}" --no-color migrate
