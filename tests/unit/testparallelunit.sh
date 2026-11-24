#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testparallelunit.sh — io::parallel contract in bash and zsh

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly PARALLEL_SH="${BS_PROJECT_ROOT}/lib/io/parallel.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

probe() {
    local sh_bin="$1"; shift
    [[ "$1" == "--" ]] && shift
    : > "${T}/probe.sh"
    local f
    for f in bootstrap/shell.sh core/prereq.sh core/const.sh core/logger.sh core/quiet.sh \
             core/utils.sh core/errorhandler.sh core/args.sh lib/io/parallel.sh; do
        printf 'BS_CURRENT_FILE="%s"; . "%s"\n' \
            "${BS_PROJECT_ROOT}/${f}" "${BS_PROJECT_ROOT}/${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "$1" >> "${T}/probe.sh"
    shift
    env -i HOME="${T}/home" PATH="/usr/bin:/bin" "$sh_bin" "${T}/probe.sh" "$@" 2>&1
}

test_parse_and_result_names() {
    local sh_bin out
    for sh_bin in bash zsh; do
        out="$(probe "$sh_bin" -- '
            io::parallel::__parse --jobs 2 --out-dir "$HOME/results" -- \
                first "two words" $'"'"'line1\nline2'"'"'
            printf "jobs=%s out=%s sched=%s n=%s name=%s\n" \
                "$IO_PARALLEL_JOBS" "$IO_PARALLEL_OUT" "$IO_PARALLEL_SCHED" \
                "${#IO_PARALLEL_ARGS[@]}" "$(io::parallel::__result_name 7)"
        ')"
        testframework::assert_equal \
            "jobs=2 out=${T}/home/results sched=pid n=3 name=0007" "$out" \
            "${sh_bin}: parser preserves arguments and formats result names"
    done
}

test_invalid_arguments() {
    local sh_bin rc out
    for sh_bin in bash zsh; do
        rc=0
        out="$(probe "$sh_bin" -- 'io::parallel::map --jobs 0 --out-dir "$HOME/r" -- true -- a')" || rc=$?
        testframework::assert_equal "2" "$rc" "${sh_bin}: zero jobs returns E_INVALID"
        rc=0
        out="$(probe "$sh_bin" -- 'io::parallel::map --jobs 2 --out-dir "$HOME/r" --scheduler bad -- true -- a')" || rc=$?
        testframework::assert_equal "2" "$rc" "${sh_bin}: unknown scheduler returns E_INVALID"
    done
}

main() {
    T="$(mktemp -d)"; mkdir -p "$T/home"; export T
    trap 'rm -rf "$T"' EXIT
    testframework::section "Parser / Парсер"; test_parse_and_result_names
    testframework::section "Invalid arguments / Неверные аргументы"; test_invalid_arguments
    testframework::summary
}

main "$@"
