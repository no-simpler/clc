#!/usr/bin/env bash
# run.sh – Snapshot test runner for clc.
#
# Usage: bash test/run.sh [--update] [<case-name> ...]
#
#   --update   Write actual output as the new snapshot instead of diffing.
#   (no args)  Run all cases against committed snapshots.
#
# Each case script creates repos under test/repos/<case>/. The runner
# discovers call sites by listing the directories created there, runs
# clc.sh --no-color from each, and compares against test/expected/<case>/<dir>.txt.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASES_DIR="${REPO_ROOT}/test/cases"
REPOS_DIR="${REPO_ROOT}/test/repos"
EXPECTED_DIR="${REPO_ROOT}/test/expected"
CLC="${REPO_ROOT}/clc.sh"

# ── Argument parsing ───────────────────────────────────────────────────────────

OPT_UPDATE=0
FILTER_CASES=()

for arg in "$@"; do
    case "${arg}" in
        --update) OPT_UPDATE=1 ;;
        -*)       echo "run.sh: unknown option: ${arg}" >&2; exit 1 ;;
        *)        FILTER_CASES+=("${arg}") ;;
    esac
done

# ── Case discovery ─────────────────────────────────────────────────────────────

cases=()
if [[ ${#FILTER_CASES[@]} -gt 0 ]]; then
    cases=("${FILTER_CASES[@]}")
else
    for f in "${CASES_DIR}"/*.sh; do
        cases+=("$(basename "${f}" .sh)")
    done
fi

# ── Run ────────────────────────────────────────────────────────────────────────

passed=0
failed=0
updated=0

check_snapshot() {
    local label="$1" snapshot="$2" actual="$3"
    if [[ ${OPT_UPDATE} -eq 1 ]]; then
        mkdir -p "$(dirname "${snapshot}")"
        printf '%s\n' "${actual}" > "${snapshot}"
        echo "[${label}] updated"
        updated=$(( updated + 1 ))
    elif [[ ! -f "${snapshot}" ]]; then
        echo "[${label}] ✗  no snapshot — run with --update to create"
        failed=$(( failed + 1 ))
    else
        local expected
        expected=$(cat "${snapshot}")
        if [[ "${actual}" == "${expected}" ]]; then
            echo "[${label}] ✓"
            passed=$(( passed + 1 ))
        else
            echo "[${label}] ✗"
            diff -u \
                --label "expected (${snapshot##*/REPO_ROOT/})" \
                --label "actual" \
                <(printf '%s\n' "${expected}") \
                <(printf '%s\n' "${actual}") | sed 's/^/  /' || true
            failed=$(( failed + 1 ))
        fi
    fi
}

run_case() {
    local case_name="$1"
    local case_script="${CASES_DIR}/${case_name}.sh"
    local action_marker="${CASES_DIR}/${case_name}.action"
    local case_repos="${REPOS_DIR}/${case_name}"
    local case_expected="${EXPECTED_DIR}/${case_name}"

    if [[ ! -f "${case_script}" ]]; then
        echo "run.sh: no such case: ${case_name}" >&2
        failed=$(( failed + 1 ))
        return
    fi

    if [[ -f "${action_marker}" ]]; then
        # Action test: capture case script output directly (it runs clc internally).
        local actual
        actual=$(bash "${case_script}" 2>&1) || true
        check_snapshot "${case_name}" "${case_expected}/output.txt" "${actual}"
    else
        # State test: suppress setup, then run clc from each worktree directory.
        if ! bash "${case_script}" > /dev/null 2>&1; then
            echo "[${case_name}] setup failed"
            failed=$(( failed + 1 ))
            rm -rf "${case_repos}"
            return
        fi

        for site_dir in "${case_repos}"/*/; do
            [[ -d "${site_dir}" ]] || continue
            local site snapshot actual
            site=$(basename "${site_dir%/}")
            snapshot="${case_expected}/${site}.txt"

            local clc_action="" cmd_file="${case_expected}/${site}.cmd"
            [[ -f "${cmd_file}" ]] && clc_action=$(cat "${cmd_file}")
            # shellcheck disable=SC2086
            actual=$(cd "${site_dir}" && bash "${CLC}" --no-color ${clc_action} 2>&1) || true
            check_snapshot "${case_name}/${site}" "${snapshot}" "${actual}"
        done
    fi

    rm -rf "${case_repos}"
}

for case_name in "${cases[@]}"; do
    run_case "${case_name}"
done

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
if [[ ${OPT_UPDATE} -eq 1 ]]; then
    echo "${updated} snapshot(s) updated"
elif [[ ${failed} -eq 0 ]]; then
    echo "${passed} passed"
else
    echo "${passed} passed, ${failed} failed"
    exit 1
fi
