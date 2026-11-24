#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testparallelunit.sh — io::parallel contract in bash and zsh

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

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
                parallel_test_worker first bad "two words"
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
                printf "start %s\n" "$$" >> "$IO_PARALLEL_OUT/events"
                sleep 0.05
                printf "end %s\n" "$$" >> "$IO_PARALLEL_OUT/events"
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

test_run_task_file() {
    local sh_bin out_dir tasks rc=0
    for sh_bin in bash zsh; do
        out_dir="$T/${sh_bin}-tasks"
        tasks="$T/${sh_bin}-tasks.txt"
        cat > "$tasks" <<'TASKS'
# comment
printf 'one\n'
printf 'two\n' >&2
false
printf 'four\n'
TASKS
        probe "$sh_bin" -- '
            io::parallel::run --jobs 2 --out-dir "$1" -- "$2"
            printf "aggregate=%s\n" "$?"
        ' _ "$out_dir" "$tasks" >/dev/null || rc=$?
        testframework::assert_equal "0" "$rc" "${sh_bin}: run returns aggregate failure, not a fatal exit"
        testframework::assert_equal "one" "$(cat "$out_dir/0000.out")" "${sh_bin}: first task stdout"
        testframework::assert_equal "two" "$(cat "$out_dir/0001.err")" "${sh_bin}: second task stderr"
        testframework::assert_equal "1" "$(cat "$out_dir/0002.rc")" "${sh_bin}: failing task rc"
        testframework::assert_equal "four" "$(cat "$out_dir/0003.out")" "${sh_bin}: later task still runs"
        rc=0
    done
}

test_fifo_scheduler() {
    local sh_bin out_dir rc=0 marker="$T/home/mkfifo.called"
    mkdir -p "$T/home/bin"
    cat > "$T/home/bin/mkfifo" <<'WRAPPER'
#!/bin/sh
printf 'called\n' >> "$HOME/mkfifo.called"
exec /usr/bin/mkfifo "$@"
WRAPPER
    chmod +x "$T/home/bin/mkfifo"
    for sh_bin in bash zsh; do
        rm -f "$marker"
        out_dir="$T/${sh_bin}-fifo"
        probe "$sh_bin" -- '
            PATH="$HOME/bin:/usr/bin:/bin"
            fifo_worker() { printf "out:%s\n" "$1"; printf "err:%s\n" "$1" >&2; [[ "$1" != bad ]]; }
            io::parallel::map --jobs 2 --scheduler fifo --out-dir "$1" -- \
                fifo_worker first bad third
            printf "aggregate=%s\n" "$?"
        ' _ "$out_dir" >/dev/null || rc=$?
        testframework::assert_equal "0" "$rc" "${sh_bin}: fifo map does not exit the caller"
        testframework::assert_true "-f '$marker'" "${sh_bin}: fifo scheduler invokes mkfifo"
        testframework::assert_equal "out:first" "$(cat "$out_dir/0000.out")" "${sh_bin}: fifo first stdout"
        testframework::assert_equal "1" "$(cat "$out_dir/0001.rc")" "${sh_bin}: fifo failure rc"
        testframework::assert_equal "out:third" "$(cat "$out_dir/0002.out")" "${sh_bin}: fifo later task runs"
        rc=0
    done
}

test_fifo_requires_mkfifo() {
    local sh_bin rc=0
    for sh_bin in bash zsh; do
        rc=0
        probe "$sh_bin" -- '
            mkdir -p "$HOME/r"
            PATH="$HOME/no-tools"
            io::parallel::map --jobs 1 --scheduler fifo --out-dir "$HOME/r" -- true a
        ' >/dev/null || rc=$?
        testframework::assert_equal "1" "$rc" "${sh_bin}: missing mkfifo returns E_ERROR"
        rc=0
    done
}

test_fifo_task_file() {
    local sh_bin out_dir tasks rc=0 marker="$T/home/mkfifo-task.called"
    mkdir -p "$T/home/bin"
    cat > "$T/home/bin/mkfifo" <<'WRAPPER'
#!/bin/sh
printf 'called\n' >> "$HOME/mkfifo-task.called"
exec /usr/bin/mkfifo "$@"
WRAPPER
    chmod +x "$T/home/bin/mkfifo"
    for sh_bin in bash zsh; do
        rm -f "$marker"
        out_dir="$T/${sh_bin}-fifo-tasks"
        tasks="$T/${sh_bin}-fifo-tasks.txt"
        cat > "$tasks" <<'TASKS'
printf 'one\n'
printf 'two\n' >&2
TASKS
        probe "$sh_bin" -- '
            PATH="$HOME/bin:/usr/bin:/bin"
            io::parallel::run --jobs 2 --scheduler fifo --out-dir "$1" -- "$2"
        ' _ "$out_dir" "$tasks" >/dev/null || rc=$?
        testframework::assert_equal "0" "$rc" "${sh_bin}: fifo task file succeeds"
        testframework::assert_true "-f '$marker'" "${sh_bin}: fifo task scheduler invokes mkfifo"
        testframework::assert_equal "one" "$(cat "$out_dir/0000.out")" "${sh_bin}: fifo task stdout"
        testframework::assert_equal "two" "$(cat "$out_dir/0001.err")" "${sh_bin}: fifo task stderr"
        rc=0
    done
}

test_fifo_burst_completion() {
    local sh_bin out_dir rc=0
    for sh_bin in bash zsh; do
        out_dir="$T/${sh_bin}-fifo-burst"
        rc=0
        probe "$sh_bin" -- '
            items=()
            for (( i=0; i<64; i++ )); do items+=("item$i"); done
            io::parallel::map --jobs 64 --scheduler fifo --out-dir "$1" -- \
                true "${items[@]}"
        ' _ "$out_dir" >/dev/null || rc=$?
        testframework::assert_equal "0" "$rc" "${sh_bin}: fifo drains a burst of workers"
        local -a rc_files=("$out_dir"/*.rc)
        testframework::assert_equal "64" \
            "${#rc_files[@]}" \
            "${sh_bin}: fifo burst writes every result"
        rc=0
    done
}

main() {
    T="$(mktemp -d)"; mkdir -p "$T/home" "$T/home/no-tools"; export T
    trap 'rm -rf "$T"' EXIT
    testframework::section "Parser / Парсер"; test_parse_and_result_names
    testframework::section "Invalid arguments / Неверные аргументы"; test_invalid_arguments
    testframework::section "PID map / PID map"; test_pid_map_contract
    testframework::section "Concurrency / Параллелизм"; test_pid_map_concurrency_limit
    testframework::section "Task file / Файл задач"; test_run_task_file
    testframework::section "FIFO / FIFO"; test_fifo_scheduler
    testframework::section "FIFO dependency / Зависимость FIFO"; test_fifo_requires_mkfifo
    testframework::section "FIFO task file / FIFO файл задач"; test_fifo_task_file
    testframework::section "FIFO burst / FIFO серия"; test_fifo_burst_completion
    testframework::summary
}

main "$@"
