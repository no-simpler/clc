#!/usr/bin/env bash
# run.sh – Snapshot test runner for clc.
#
# Usage: bash test/run.sh [--update] [<case-name> ...]
#
#   --update   Write actual output as the new snapshot instead of diffing.
#   (no args)  Run all cases against committed snapshots.
#
# Each case script in test/cases/<case>.sh sets up worktrees under
# test/playground/<case>/ and optionally calls clc to produce action output.
#
# Snapshot conventions in test/expected/<case>/:
#   output.action.txt        – compared against stdout of case script (optional)
#   output.<worktree>.txt    – runner cd's into test/playground/<case>/<worktree>/,
#                              runs clc --no-color, and compares (optional, repeatable)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASES_DIR="${REPO_ROOT}/test/cases"
PLAYGROUND_DIR="${REPO_ROOT}/test/playground"
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

normalize_output() {
    # Replace actual parent dir path with a stable placeholder so snapshots are
    # machine-independent. Both ${HOME}-shortened and absolute forms are replaced.
    local out="$1" parent_disp="$2" parent_abs="$3"
    out="${out//${parent_disp}/%%PARENT_DIR%%}"
    out="${out//${parent_abs}/%%PARENT_DIR%%}"
    printf '%s' "${out}"
}

run_case() {
    local case_name="$1"
    local case_script="${CASES_DIR}/${case_name}.sh"
    local case_playground="${PLAYGROUND_DIR}/${case_name}"
    local case_expected="${EXPECTED_DIR}/${case_name}"

    if [[ ! -f "${case_script}" ]]; then
        echo "run.sh: no such case: ${case_name}" >&2
        failed=$(( failed + 1 ))
        return
    fi

    # Parent dir displayed in status output (same logic as short_path in clc.sh).
    local parent_dir_abs parent_dir_disp
    parent_dir_abs="${case_playground}"
    parent_dir_disp="${case_playground/#${HOME}/\~}"

    # Step 1: Run case script, capture stdout and stderr.
    local action_out
    action_out=$(bash "${case_script}" 2>&1) || true

    # Step 2: Assert action output.
    # On --update: write if stdout is non-empty. On compare: check if file exists.
    local action_snapshot="${case_expected}/output.action.txt"
    local action_normalized
    action_normalized=$(normalize_output "${action_out}" "${parent_dir_disp}" "${parent_dir_abs}")
    if [[ ${OPT_UPDATE} -eq 1 && -n "${action_out}" ]]; then
        check_snapshot "${case_name}/action" "${action_snapshot}" "${action_normalized}"
    elif [[ -f "${action_snapshot}" ]]; then
        check_snapshot "${case_name}/action" "${action_snapshot}" "${action_normalized}"
    fi

    # Step 3: Assert per-worktree status output.
    if [[ ${OPT_UPDATE} -eq 1 ]]; then
        # Update mode: discover worktrees from filesystem.
        for wt_dir in "${case_playground}"/*/; do
            [[ -d "${wt_dir}" ]] || continue
            local wt snapshot actual wt_normalized
            wt=$(basename "${wt_dir%/}")
            snapshot="${case_expected}/output.${wt}.txt"
            actual=$(cd "${wt_dir}" && bash "${CLC}" --no-color 2>&1) || true
            wt_normalized=$(normalize_output "${actual}" "${parent_dir_disp}" "${parent_dir_abs}")
            check_snapshot "${case_name}/${wt}" "${snapshot}" "${wt_normalized}"
        done
    else
        # Compare mode: check only worktrees that have expected files.
        for snapshot in "${case_expected}"/output.*.txt; do
            [[ -f "${snapshot}" ]] || continue
            local filename wt_name wt_dir actual wt_normalized
            filename=$(basename "${snapshot}")
            [[ "${filename}" == "output.action.txt" ]] && continue
            wt_name="${filename#output.}"
            wt_name="${wt_name%.txt}"
            wt_dir="${case_playground}/${wt_name}"
            actual=$(cd "${wt_dir}" && bash "${CLC}" --no-color 2>&1) || true
            wt_normalized=$(normalize_output "${actual}" "${parent_dir_disp}" "${parent_dir_abs}")
            check_snapshot "${case_name}/${wt_name}" "${snapshot}" "${wt_normalized}"
        done
    fi

    rm -rf "${case_playground}"
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
