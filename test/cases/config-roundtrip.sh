#!/usr/bin/env bash
# config-roundtrip.sh – Exercise the v2 config helpers by sourcing clc.sh.
#
# The source-guard at the bottom of clc.sh prevents main from running when the
# file is sourced, so we can unit-test the config_get/config_set/config_list
# helpers directly. Output is deterministic and contains no machine paths.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_DIR="${REPO_ROOT}/test/playground/config-roundtrip"
CLC="${REPO_ROOT}/clc.sh"
rm -rf "${CASE_DIR}"; mkdir -p "${CASE_DIR}"

# Isolate XDG so the helper resolves into the playground (run.sh also sets these,
# but set explicitly here so the case is self-contained and path-stable).
# Use a dot-prefixed subdir so the runner's "*/" worktree glob doesn't pick it
# up as a worktree (which would emit a non-deterministic state snapshot).
export XDG_CONFIG_HOME="${CASE_DIR}/.config"
unset CLC_STORE 2>/dev/null || true

# shellcheck source=/dev/null
source "${CLC}"

echo "get-missing: [$(config_get demo.key)]"
config_set demo.key hello
echo "get-present: [$(config_get demo.key)]"
config_set demo.key world
echo "get-updated: [$(config_get demo.key)]"
config_list
