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
    [[ "${1:-}" == "_" ]] && shift
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
        out="$(probe "$sh_bin" -- 'io::parallel::map --jobs 0 --out-dir "$HOME/r" -- true a')" || rc=$?
        testframework::assert_equal "2" "$rc" "${sh_bin}: zero jobs returns E_INVALID"
        rc=0
        out="$(probe "$sh_bin" -- 'io::parallel::map --jobs 2 --out-dir "$HOME/r" --scheduler bad -- true a')" || rc=$?
        testframework::assert_equal "2" "$rc" "${sh_bin}: unknown scheduler returns E_INVALID"
    done
}

parallel_test_worker() {
    local item="$1"
    printf 'out:%s\n' "$item"
    printf 'err:%s\n' "$item" >&2
    [[ "$item" != bad ]]
}

test_pid_map_contract() {
    local sh_bin out_dir out rc=0
    for sh_bin in bash zsh; do
        out_dir="$T/${sh_bin}-pid"
        out="$(probe "$sh_bin" -- '
            parallel_test_worker() {
                local item="$1"
                printf "out:%s\n" "$item"
                printf "err:%s\n" "$item" >&2
                [[ "$item" != bad ]]
            }
            io::parallel::map --jobs 2 --out-dir "$1" -- \
                parallel_test_worker -- first bad "two words"
            printf "aggregate=%s\n" "$?"
        ' _ "$out_dir")" || rc=$?
        testframework::assert_equal "0" "$rc" "${sh_bin}: map itself returns success"
        testframework::assert_equal "out:first" "$(cat "$out_dir/0000.out")" "${sh_bin}: first stdout"
        testframework::assert_equal "err:first" "$(cat "$out_dir/0000.err")" "${sh_bin}: first stderr"
        testframework::assert_equal "0" "$(cat "$out_dir/0000.rc")" "${sh_bin}: first rc"
        testframework::assert_equal "out:bad" "$(cat "$out_dir/0001.out")" "${sh_bin}: failing worker stdout"
        testframework::assert_equal "1" "$(cat "$out_dir/0001.rc")" "${sh_bin}: failing worker rc"
        testframework::assert_equal "out:two words" "$(cat "$out_dir/0002.out")" "${sh_bin}: spaces preserved"
        testframework::assert_command "grep -q 'aggregate=1' <<< '$out'" "${sh_bin}: aggregate failure is reported"
        rc=0
    done
}

test_pid_map_concurrency_limit() {
    local sh_bin out_dir out rc=0
    for sh_bin in bash zsh; do
        out_dir="$T/${sh_bin}-limit"
        out="$(probe "$sh_bin" -- '
            slow_worker() {
                printf "start %s\n" "$$" >> "$1/events"
                sleep 0.05
                printf "end %s\n" "$$" >> "$1/events"
            }
            io::parallel::map --jobs 2 --out-dir "$1" -- slow_worker a b c d e
        ' _ "$out_dir")" || rc=$?
        testframework::assert_equal "0" "$rc" "${sh_bin}: bounded map succeeds"
        testframework::assert_equal "2" \
            "$(awk '$1=="start"{n++; if(n>m)m=n} $1=="end"{n--} END{print m}' "$out_dir/events")" \
            "${sh_bin}: concurrency never exceeds jobs"
        rc=0
    done
}

main() {
    T="$(mktemp -d)"; mkdir -p "$T/home"; export T
    trap 'rm -rf "$T"' EXIT
    testframework::section "Parser / Парсер"; test_parse_and_result_names
    testframework::section "Invalid arguments / Неверные аргументы"; test_invalid_arguments
    testframework::section "PID map / PID map"; test_pid_map_contract
    testframework::section "Concurrency / Параллелизм"; test_pid_map_concurrency_limit
    testframework::summary
}

main "$@"
