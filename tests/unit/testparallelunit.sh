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
    if [[ -n "${PROBE_TIMEOUT:-}" ]]; then
        timeout -k 1 "$PROBE_TIMEOUT" env -i HOME="${T}/home" PATH="/usr/bin:/bin" \
            "$sh_bin" "${T}/probe.sh" "$@" 2>&1
    else
        env -i HOME="${T}/home" PATH="/usr/bin:/bin" "$sh_bin" "${T}/probe.sh" "$@" 2>&1
    fi
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
    local sh_bin jobs rc out
    for sh_bin in bash zsh; do
        for jobs in 0 2147483648 9999999999 18446744073709551616; do
            rc=0
            out="$(probe "$sh_bin" -- 'io::parallel::map --jobs "$1" --out-dir "$HOME/r" -- true a' _ "$jobs")" || rc=$?
            testframework::assert_equal "2" "$rc" "${sh_bin}: invalid jobs ${jobs} returns E_INVALID"
        done
        rc=0
        out="$(probe "$sh_bin" -- 'io::parallel::map --jobs 2 --out-dir "$HOME/r" --scheduler bad -- true a')" || rc=$?
        testframework::assert_equal "2" "$rc" "${sh_bin}: unknown scheduler returns E_INVALID"
    done
}

test_help_keeps_stdout_clean() {
    local sh_bin out rc=0
    for sh_bin in bash zsh; do
        rc=0
        out="$(probe "$sh_bin" -- '
            io::parallel::map --help > "$HOME/help.out" 2> "$HOME/help.err"
            printf "rc=%s\n" "$?"
        ')" || rc=$?
        testframework::assert_equal "0" "$rc" "${sh_bin}: help probe succeeds"
        testframework::assert_equal "rc=0" "$out" "${sh_bin}: help returns E_SUCCESS"
        testframework::assert_equal "" "$(cat "$T/home/help.out")" "${sh_bin}: help keeps stdout clean"
        testframework::assert_command "grep -q -- '--jobs' '$T/home/help.err'" "${sh_bin}: help documents jobs on stderr"
        rc=0
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
   # indented comment
printf 'one\n'
printf 'two\n' >&2
false
printf 'four\n'
TASKS
        printf '   \n' >> "$tasks"
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
    local sh_bin out_dir out rc=0 marker="$T/home/mkfifo.called"
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
        out="$(probe "$sh_bin" -- '
            PATH="$HOME/bin:/usr/bin:/bin"
            fifo_worker() { printf "out:%s\n" "$1"; printf "err:%s\n" "$1" >&2; [[ "$1" != bad ]]; }
            io::parallel::map --jobs 2 --scheduler fifo --out-dir "$1" -- \
                fifo_worker first bad third
            printf "aggregate=%s\n" "$?"
        ' _ "$out_dir")" || rc=$?
        testframework::assert_equal "0" "$rc" "${sh_bin}: fifo map does not exit the caller"
        testframework::assert_equal "aggregate=1" "$out" "${sh_bin}: fifo map keeps stdout clean"
        testframework::assert_true "-f '$marker'" "${sh_bin}: fifo scheduler invokes mkfifo"
        testframework::assert_equal "out:first" "$(cat "$out_dir/0000.out")" "${sh_bin}: fifo first stdout"
        testframework::assert_equal "1" "$(cat "$out_dir/0001.rc")" "${sh_bin}: fifo failure rc"
        testframework::assert_equal "out:third" "$(cat "$out_dir/0002.out")" "${sh_bin}: fifo later task runs"
        rc=0
    done
}

test_fifo_requires_mkfifo() {
    local sh_bin out rc=0
    mkdir -p "$T/home/no-mkfifo-bin"
    ln -s "$(command -v mkdir)" "$T/home/no-mkfifo-bin/mkdir"
    ln -s "$(command -v mktemp)" "$T/home/no-mkfifo-bin/mktemp"
    ln -s "$(command -v rm)" "$T/home/no-mkfifo-bin/rm"
    for sh_bin in bash zsh; do
        rc=0
        out="$(probe "$sh_bin" -- '
            mkdir -p "$HOME/r"
            PATH="$HOME/no-mkfifo-bin"
            io::parallel::map --jobs 1 --scheduler fifo --out-dir "$HOME/r" -- true a
        ')" || rc=$?
        testframework::assert_equal "1" "$rc" "${sh_bin}: missing mkfifo returns E_ERROR"
        testframework::assert_command "grep -q 'requires mkfifo' <<< '$out'" \
            "${sh_bin}: missing mkfifo names the dependency"
        rc=0
    done
}

test_fifo_task_file() {
    local sh_bin out_dir tasks out rc=0 marker="$T/home/mkfifo-task.called"
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
        out="$(probe "$sh_bin" -- '
            PATH="$HOME/bin:/usr/bin:/bin"
            io::parallel::run --jobs 2 --scheduler fifo --out-dir "$1" -- "$2"
        ' _ "$out_dir" "$tasks")" || rc=$?
        testframework::assert_equal "0" "$rc" "${sh_bin}: fifo task file succeeds"
        testframework::assert_equal "" "$out" "${sh_bin}: fifo task file keeps stdout clean"
        testframework::assert_true "-f '$marker'" "${sh_bin}: fifo task scheduler invokes mkfifo"
        testframework::assert_equal "one" "$(cat "$out_dir/0000.out")" "${sh_bin}: fifo task stdout"
        testframework::assert_equal "two" "$(cat "$out_dir/0001.err")" "${sh_bin}: fifo task stderr"
        rc=0
    done
}

test_fifo_burst_completion() {
    local sh_bin out_dir out rc=0
    for sh_bin in bash zsh; do
        out_dir="$T/${sh_bin}-fifo-burst"
        rc=0
        out="$(probe "$sh_bin" -- '
            items=()
            for (( i=0; i<64; i++ )); do items+=("item$i"); done
            io::parallel::map --jobs 64 --scheduler fifo --out-dir "$1" -- \
                true "${items[@]}"
        ' _ "$out_dir")" || rc=$?
        testframework::assert_equal "" "$out" "${sh_bin}: fifo burst keeps stdout clean"
        testframework::assert_equal "0" "$rc" "${sh_bin}: fifo drains a burst of workers"
        local -a rc_files=("$out_dir"/*.rc)
        testframework::assert_equal "64" \
            "${#rc_files[@]}" \
            "${sh_bin}: fifo burst writes every result"
        rc=0
    done
}

test_xargs_stub() {
    local sh_bin out_dir tasks out rc=0
    for sh_bin in bash zsh; do
        out_dir="$T/${sh_bin}-xargs-stub"
        rc=0
        out="$(probe "$sh_bin" -- '
            io::parallel::map --jobs 2 --scheduler xargs --out-dir "$1" -- true first
            rc=$?
            printf "temp=%s fd=%s\n" "$IO_PARALLEL_TEMP" "$IO_PARALLEL_FD"
            exit "$rc"
        ' _ "$out_dir")" || rc=$?
        testframework::assert_equal "1" "$rc" "${sh_bin}: xargs map returns E_ERROR"
        testframework::assert_false "-e '$out_dir'" "${sh_bin}: xargs stub creates no result directory"
        testframework::assert_command "grep -q '^temp= fd=$' <<< '$out'" \
            "${sh_bin}: xargs map leaves no temporary state"

        tasks="$T/${sh_bin}-xargs-stub-tasks.txt"
        cat > "$tasks" <<'TASKS'
printf 'one\n'
TASKS
        out_dir="$T/${sh_bin}-xargs-stub-tasks"
        rc=0
        out="$(probe "$sh_bin" -- '
            io::parallel::run --jobs 2 --scheduler xargs --out-dir "$1" -- "$2"
            rc=$?
            printf "temp=%s fd=%s\n" "$IO_PARALLEL_TEMP" "$IO_PARALLEL_FD"
            exit "$rc"
        ' _ "$out_dir" "$tasks")" || rc=$?
        testframework::assert_equal "1" "$rc" "${sh_bin}: xargs run returns E_ERROR"
        testframework::assert_false "-e '$out_dir'" "${sh_bin}: xargs stub creates no task results"
        testframework::assert_command "grep -q '^temp= fd=$' <<< '$out'" \
            "${sh_bin}: xargs run leaves no temporary state"
        rc=0
    done
}

test_empty_and_clean_output() {
    local sh_bin scheduler out_dir tasks out rc=0
    for sh_bin in bash zsh; do
        for scheduler in pid fifo; do
            out_dir="$T/${sh_bin}-${scheduler}-empty"
            rc=0
            out="$(probe "$sh_bin" -- '
                set -euo pipefail
            io::parallel::map --jobs 2 --scheduler "$2" --out-dir "$1" -- true
            ' _ "$out_dir" "$scheduler")" || rc=$?
            testframework::assert_equal "0" "$rc" "${sh_bin}/${scheduler}: empty map succeeds"
            testframework::assert_equal "" "$out" "${sh_bin}/${scheduler}: empty map keeps stdout clean"
            testframework::assert_false "-e '$out_dir/0000.rc'" "${sh_bin}/${scheduler}: empty map writes no results"

            tasks="$T/${sh_bin}-${scheduler}-empty.txt"
            printf '# comment\n\n' > "$tasks"
            out_dir="$T/${sh_bin}-${scheduler}-empty-tasks"
            rc=0
            out="$(probe "$sh_bin" -- '
                set -euo pipefail
            io::parallel::run --jobs 2 --scheduler "$3" --out-dir "$1" -- "$2"
            ' _ "$out_dir" "$tasks" "$scheduler")" || rc=$?
            testframework::assert_equal "0" "$rc" "${sh_bin}/${scheduler}: empty task file succeeds"
            testframework::assert_equal "" "$out" "${sh_bin}/${scheduler}: empty run keeps stdout clean"
            testframework::assert_false "-e '$out_dir/0000.rc'" "${sh_bin}/${scheduler}: empty run writes no results"
            rc=0
        done
    done
}

test_special_items() {
    local sh_bin scheduler out_dir rc=0
    local newline_item=$'line1\nline2'
    for sh_bin in bash zsh; do
        for scheduler in pid fifo; do
            out_dir="$T/${sh_bin}-${scheduler}-special"
            rc=0
            probe "$sh_bin" -- '
                worker() { printf "%s" "$1"; }
                io::parallel::map --jobs 2 --scheduler "$3" --out-dir "$1" -- \
                    worker "$2" --jobs
            ' _ "$out_dir" "$newline_item" "$scheduler" >/dev/null || rc=$?
            testframework::assert_equal "0" "$rc" "${sh_bin}/${scheduler}: special items succeed"
            testframework::assert_equal "$newline_item" "$(cat "$out_dir/0000.out")" \
                "${sh_bin}/${scheduler}: newline stays inside one argument"
            testframework::assert_equal "--jobs" "$(cat "$out_dir/0001.out")" \
                "${sh_bin}/${scheduler}: leading dash stays positional after separator"
            rc=0
        done
    done
}

test_cancel_cleans_workers() {
    local sh_bin scheduler signal out_dir out worker_pid rc=0
    for sh_bin in bash zsh; do
        for scheduler in pid fifo; do
            for signal in INT TERM; do
                out_dir="$T/${sh_bin}-${scheduler}-${signal}-cancel"
                rc=0
                out="$(probe "$sh_bin" -- '
                    pool_pid=$$
                    export CANCEL_DIR="$3"
                    (
                        for (( i=0; i<100; i++ )); do
                            [[ -f "$CANCEL_DIR/ready" ]] && break
                            sleep 0.01
                        done
                        kill -"$1" "$pool_pid"
                    ) &
                    sender=$!
                    slow_task() {
                        printf "%s\n" "$IO_PARALLEL_TEMP" > "$CANCEL_DIR/temp-path"
                        exec bash -c '\''
                            printf "%s\\n" "$$" > "$CANCEL_DIR/worker.pid"
                            : > "$CANCEL_DIR/ready"
                            sleep 0.5
                            printf "leaked\\n" > "$CANCEL_DIR/leaked"
                        '\''
                    }
                    io::parallel::map --jobs 1 --scheduler "$2" --out-dir "$3" -- \
                        slow_task unused
                    rc=$?
                    wait "$sender" || true
                    printf "rc=%s temp=%s fd=%s\\n" "$rc" "$IO_PARALLEL_TEMP" "$IO_PARALLEL_FD"
                    exit 0
                ' _ "$signal" "$scheduler" "$out_dir")" || rc=$?
                testframework::assert_equal "0" "$rc" "${sh_bin}/${scheduler}/${signal}: probe survives signal"
                sleep 0.6
                if [[ -f "$out_dir/worker.pid" ]]; then
                    worker_pid="$(cat "$out_dir/worker.pid")"
                    [[ "$worker_pid" =~ ^[1-9][0-9]*$ ]] && kill -TERM "$worker_pid" 2>/dev/null || true
                fi
                testframework::assert_false "-f '$out_dir/leaked'" \
                    "${sh_bin}/${scheduler}/${signal}: cancellation prevents worker side effects"
                testframework::assert_command "grep -q '^rc=1 temp= fd=$' <<< '$out'" \
                    "${sh_bin}/${scheduler}/${signal}: cancellation returns E_ERROR and clears state"
                if [[ "$scheduler" == "fifo" && -f "$out_dir/temp-path" ]]; then
                    testframework::assert_false "-e '$(cat "$out_dir/temp-path")'" \
                        "${sh_bin}/${scheduler}/${signal}: cancellation removes FIFO temporary directory"
                fi
                rc=0
            done
        done
    done
}

test_programmatic_cancel() {
    local sh_bin mode out_dir tasks out worker_pid rc=0
    local PROBE_TIMEOUT=5
    for sh_bin in bash zsh; do
        for mode in map run; do
            out_dir="$T/${sh_bin}-fifo-cancel-${mode}"
            tasks="$T/${sh_bin}-fifo-cancel-${mode}.txt"
            cat > "$tasks" <<'TASKS'
printf '%s\n' "$$" > "$CANCEL_DIR/worker.pid"
: > "$CANCEL_DIR/ready"
sleep 0.5
printf 'leaked\n' > "$CANCEL_DIR/leaked"
TASKS
            rc=0
            out="$(probe "$sh_bin" -- '
                pool_pid=$$
                export CANCEL_DIR="$3"
                cancel_on_usr1() { io::parallel::cancel; }
                trap cancel_on_usr1 USR1
                (
                    for (( i=0; i<100; i++ )); do
                        [[ -f "$CANCEL_DIR/ready" ]] && break
                        sleep 0.01
                    done
                    kill -USR1 "$pool_pid"
                ) &
                sender=$!
                if [[ "$1" == map ]]; then
                    slow_task() {
                        printf "%s\n" "$IO_PARALLEL_TEMP" > "$CANCEL_DIR/temp-path"
                        exec bash -c '\''
                            printf "%s\\n" "$$" > "$CANCEL_DIR/worker.pid"
                            : > "$CANCEL_DIR/ready"
                            sleep 0.5
                            printf "leaked\\n" > "$CANCEL_DIR/leaked"
                        '\''
                    }
                    if io::parallel::map --jobs 1 --scheduler fifo --out-dir "$3" -- \
                        slow_task unused; then rc=0; else rc=$?; fi
                else
                    if io::parallel::run --jobs 1 --scheduler fifo --out-dir "$3" -- "$2"; then
                        rc=0
                    else
                        rc=$?
                    fi
                fi
                wait "$sender" || true
                printf "rc=%s temp=%s fd=%s\n" "$rc" "$IO_PARALLEL_TEMP" "$IO_PARALLEL_FD"
                exit 0
            ' _ "$mode" "$tasks" "$out_dir")" || rc=$?
            sleep 0.6
            if [[ -f "$out_dir/worker.pid" ]]; then
                worker_pid="$(cat "$out_dir/worker.pid")"
                [[ "$worker_pid" =~ ^[1-9][0-9]*$ ]] && kill -TERM "$worker_pid" 2>/dev/null || true
            fi
            testframework::assert_equal "0" "$rc" "${sh_bin}/${mode}: programmatic cancel does not hang"
            testframework::assert_false "-f '$out_dir/leaked'" \
                "${sh_bin}/${mode}: programmatic cancel prevents worker side effects"
            testframework::assert_command "grep -q '^rc=1 temp= fd=$' <<< '$out'" \
                "${sh_bin}/${mode}: programmatic cancel returns E_ERROR and clears state"
            if [[ "$mode" == map && -f "$out_dir/temp-path" ]]; then
                testframework::assert_false "-e '$(cat "$out_dir/temp-path")'" \
                    "${sh_bin}/${mode}: programmatic cancel removes FIFO temporary directory"
            fi
            rc=0
        done
    done
}

test_result_persistence_failures() {
    local sh_bin scheduler mode out_dir tasks out rc=0
    local PROBE_TIMEOUT=5
    for sh_bin in bash zsh; do
        for scheduler in pid fifo; do
            for mode in map run; do
                out_dir="$T/${sh_bin}-${scheduler}-${mode}-persist"
                mkdir -p "$out_dir/0000.rc"
                tasks="$T/${sh_bin}-${scheduler}-${mode}-persist.txt"
                printf 'true\ntrue\n' > "$tasks"
                rc=0
                out="$(probe "$sh_bin" -- '
                    set -e
                    if [[ "$1" == map ]]; then
                        if io::parallel::map --jobs 1 --scheduler "$2" --out-dir "$3" -- true a b; then
                            rc=0
                        else
                            rc=$?
                        fi
                    else
                        if io::parallel::run --jobs 1 --scheduler "$2" --out-dir "$3" -- "$4"; then
                            rc=0
                        else
                            rc=$?
                        fi
                    fi
                    printf "rc=%s\n" "$rc"
                ' _ "$mode" "$scheduler" "$out_dir" "$tasks")" || rc=$?
                testframework::assert_equal "0" "$rc" "${sh_bin}/${scheduler}/${mode}: persistence failure does not hang"
                testframework::assert_command "grep -q '^rc=1$' <<< '$out'" \
                    "${sh_bin}/${scheduler}/${mode}: persistence failure is E_ERROR"
                testframework::assert_equal "0" "$(cat "$out_dir/0001.rc")" \
                    "${sh_bin}/${scheduler}/${mode}: later task still persists"
                rc=0
            done
        done
    done
}

test_result_symlinks_replaced() {
    local sh_bin scheduler out_dir victim_out victim_err victim_rc rc=0
    for sh_bin in bash zsh; do
        for scheduler in pid fifo; do
            out_dir="$T/${sh_bin}-${scheduler}-symlink"
            mkdir -p "$out_dir"
            victim_out="$T/${sh_bin}-${scheduler}-victim.out"
            victim_err="$T/${sh_bin}-${scheduler}-victim.err"
            victim_rc="$T/${sh_bin}-${scheduler}-victim.rc"
            printf 'keep-out\n' > "$victim_out"
            printf 'keep-err\n' > "$victim_err"
            printf 'keep-rc\n' > "$victim_rc"
            ln -s "$victim_out" "$out_dir/0000.out"
            ln -s "$victim_err" "$out_dir/0000.err"
            ln -s "$victim_rc" "$out_dir/0000.rc"
            rc=0
            probe "$sh_bin" -- '
                worker() { printf "safe\n"; printf "diagnostic\n" >&2; }
                io::parallel::map --jobs 1 --scheduler "$2" --out-dir "$1" -- worker item
            ' _ "$out_dir" "$scheduler" >/dev/null || rc=$?
            testframework::assert_equal "0" "$rc" "${sh_bin}/${scheduler}: symlink run succeeds"
            testframework::assert_equal "keep-out" "$(cat "$victim_out")" "${sh_bin}/${scheduler}: stdout symlink target untouched"
            testframework::assert_equal "keep-err" "$(cat "$victim_err")" "${sh_bin}/${scheduler}: stderr symlink target untouched"
            testframework::assert_equal "keep-rc" "$(cat "$victim_rc")" "${sh_bin}/${scheduler}: rc symlink target untouched"
            testframework::assert_false "-L '$out_dir/0000.out' -o -L '$out_dir/0000.err' -o -L '$out_dir/0000.rc'" \
                "${sh_bin}/${scheduler}: result symlinks are replaced by regular files"
            testframework::assert_equal "safe" "$(cat "$out_dir/0000.out")" "${sh_bin}/${scheduler}: safe stdout is published"
            testframework::assert_equal "0" "$(cat "$out_dir/0000.rc")" "${sh_bin}/${scheduler}: safe rc is published"
            rc=0
        done
    done
}

test_signal_handlers_restored() {
    local sh_bin scheduler disposition out rc=0
    for sh_bin in bash zsh; do
        for scheduler in pid fifo; do
            for disposition in custom ignored default; do
                out="$T/${sh_bin}-${scheduler}-${disposition}-results"
                rc=0
                out="$(probe "$sh_bin" -- '
                    snapshot_traps() {
                        if [[ -n "${ZSH_VERSION:-}" ]]; then trap; else trap -p INT TERM; fi
                    }
                    term_seen=0; int_seen=0
                    custom_term() { term_seen=1; }
                    custom_int() { int_seen=1; }
                    case "$1" in
                        custom)  trap custom_int INT; trap custom_term TERM ;;
                        ignored) trap "" INT; trap "" TERM ;;
                        default) trap - INT; trap - TERM ;;
                    esac
                    before="$(snapshot_traps)"
                    io::parallel::map --jobs 1 --scheduler "$2" --out-dir "$3" -- true item
                    after="$(snapshot_traps)"
                    [[ "$before" == "$after" ]]; same_rc=$?
                    if [[ "$1" != default ]]; then
                        kill -TERM "$$"
                        kill -INT "$$"
                    fi
                    printf "same=%s term=%s int=%s\n" "$same_rc" "$term_seen" "$int_seen"
                ' _ "$disposition" "$scheduler" "$out")" || rc=$?
                testframework::assert_equal "0" "$rc" "${sh_bin}/${scheduler}/${disposition}: probe survives"
                local expected="same=0 term=0 int=0"
                [[ "$disposition" == custom ]] && expected="same=0 term=1 int=1"
                testframework::assert_equal "$expected" "$out" \
                    "${sh_bin}/${scheduler}/${disposition}: caller signal handlers are restored"
                rc=0
            done
        done
    done
}

test_option_like_output_directory() {
    local sh_bin scheduler dir_name base out_dir rc=0
    for sh_bin in bash zsh; do
        for scheduler in pid fifo; do
            for dir_name in --help -results; do
                base="$T/${sh_bin}-${scheduler}-${dir_name#-}"
                mkdir -p "$base"
                out_dir="$base/$dir_name"
                rc=0
                out="$(probe "$sh_bin" -- '
                    cd "$1"
                    io::parallel::map --jobs 1 --scheduler "$3" --out-dir "$2" -- true item
                ' _ "$base" "$dir_name" "$scheduler")" || rc=$?
                testframework::assert_equal "0" "$rc" "${sh_bin}/${scheduler}/${dir_name}: option-like directory succeeds"
                testframework::assert_equal "" "$out" "${sh_bin}/${scheduler}/${dir_name}: option-like directory keeps stdout clean"
                local -a staging=("$out_dir"/.bs-parallel.*)
                testframework::assert_false "-e '${staging[0]}'" \
                    "${sh_bin}/${scheduler}/${dir_name}: staging directory is removed"
                testframework::assert_equal "0" "$(cat "$out_dir/0000.rc")" \
                    "${sh_bin}/${scheduler}/${dir_name}: option-like directory receives results"
                rc=0
            done
        done
    done
}

test_callback_exit_exec() {
    local sh_bin scheduler mode out_dir tasks out rc=0
    local PROBE_TIMEOUT=5
    for sh_bin in bash zsh; do
        for scheduler in pid fifo; do
            for mode in map run; do
                out_dir="$T/${sh_bin}-${scheduler}-${mode}-exit-exec"
                tasks="$T/${sh_bin}-${scheduler}-${mode}-exit-exec.txt"
                printf 'exit 7\nexec true\n' > "$tasks"
                rc=0
                out="$(probe "$sh_bin" -- '
                    set -e
                    worker() {
                        if [[ "$1" == exit ]]; then exit 7; else exec true; fi
                    }
                    if [[ "$1" == map ]]; then
                        if io::parallel::map --jobs 1 --scheduler "$2" --out-dir "$3" -- \
                            worker exit exec; then rc=0; else rc=$?; fi
                    else
                        if io::parallel::run --jobs 1 --scheduler "$2" --out-dir "$3" -- "$4"; then
                            rc=0
                        else
                            rc=$?
                        fi
                    fi
                    printf "rc=%s\n" "$rc"
                ' _ "$mode" "$scheduler" "$out_dir" "$tasks")" || rc=$?
                testframework::assert_equal "0" "$rc" "${sh_bin}/${scheduler}/${mode}: callback exit/exec probe survives"
                testframework::assert_equal "rc=1" "$out" "${sh_bin}/${scheduler}/${mode}: callback exit is aggregated"
                testframework::assert_equal "7" "$(cat "$out_dir/0000.rc")" \
                    "${sh_bin}/${scheduler}/${mode}: callback exit status is persisted"
                testframework::assert_equal "0" "$(cat "$out_dir/0001.rc")" \
                    "${sh_bin}/${scheduler}/${mode}: exec callback still reports completion"
                rc=0
            done
        done
    done
}

test_publication_race() {
    local sh_bin scheduler out_dir victim real_mv rc=0
    real_mv="$(command -v mv)"
    mkdir -p "$T/home/race-bin"
    cat > "$T/home/race-bin/mv" <<'WRAPPER'
#!/bin/sh
dst=""
for arg in "$@"; do dst="$arg"; done
rm -f -- "$dst"
ln -s "$RACE_VICTIM_DIR" "$dst"
exec "$REAL_MV" "$@"
WRAPPER
    chmod +x "$T/home/race-bin/mv"
    for sh_bin in bash zsh; do
        for scheduler in pid fifo; do
            out_dir="$T/${sh_bin}-${scheduler}-race"
            victim="$T/${sh_bin}-${scheduler}-race-victim"
            mkdir -p "$out_dir" "$victim"
            printf 'keep\n' > "$victim/victim"
            rc=0
            probe "$sh_bin" -- '
                export RACE_VICTIM_DIR="$2" REAL_MV="$4"
                PATH="$HOME/race-bin:/usr/bin:/bin"
                worker() { printf "safe\n"; }
                io::parallel::map --jobs 1 --scheduler "$3" --out-dir "$1" -- worker item
            ' _ "$out_dir" "$victim" "$scheduler" "$real_mv" >/dev/null || rc=$?
            testframework::assert_true "$rc -eq 0 || $rc -eq 1" \
                "${sh_bin}/${scheduler}: publication race succeeds safely or fails closed"
            testframework::assert_equal "keep" "$(cat "$victim/victim")" \
                "${sh_bin}/${scheduler}: race cannot write into victim directory"
            local -a victim_entries=("$victim"/*)
            testframework::assert_equal "1" "${#victim_entries[@]}" \
                "${sh_bin}/${scheduler}: victim directory receives no result files"
            if (( rc == 0 )); then
                testframework::assert_false "-L '$out_dir/0000.out'" \
                    "${sh_bin}/${scheduler}: raced destination symlink is replaced"
                testframework::assert_equal "safe" "$(cat "$out_dir/0000.out")" \
                    "${sh_bin}/${scheduler}: raced result is published safely"
            else
                testframework::assert_false "-e '$out_dir/0000.out'" \
                    "${sh_bin}/${scheduler}: unsupported race replacement fails closed"
            fi
            rc=0
        done
    done
}

test_empty_read_only_directory() {
    local sh_bin scheduler mode out_dir tasks rc=0
    for sh_bin in bash zsh; do
        for scheduler in pid fifo; do
            for mode in map run; do
                out_dir="$T/${sh_bin}-${scheduler}-${mode}-readonly"
                mkdir -p "$out_dir"
                chmod 555 "$out_dir"
                tasks="$T/${sh_bin}-${scheduler}-${mode}-readonly.txt"
                printf '# no work\n\n' > "$tasks"
                rc=0
                probe "$sh_bin" -- '
                    if [[ "$1" == map ]]; then
                        io::parallel::map --jobs 1 --scheduler "$2" --out-dir "$3" -- true
                    else
                        io::parallel::run --jobs 1 --scheduler "$2" --out-dir "$3" -- "$4"
                    fi
                ' _ "$mode" "$scheduler" "$out_dir" "$tasks" >/dev/null || rc=$?
                chmod 755 "$out_dir"
                testframework::assert_equal "0" "$rc" "${sh_bin}/${scheduler}/${mode}: empty work succeeds in read-only directory"
                rc=0
            done
        done
    done
}

main() {
    T="$(mktemp -d)"; mkdir -p "$T/home" "$T/home/no-tools"; export T
    trap 'rm -rf "$T"' EXIT
    testframework::section "Parser / Парсер"; test_parse_and_result_names
    testframework::section "Invalid arguments / Неверные аргументы"; test_invalid_arguments
    testframework::section "Help / Справка"; test_help_keeps_stdout_clean
    testframework::section "PID map / PID map"; test_pid_map_contract
    testframework::section "Concurrency / Параллелизм"; test_pid_map_concurrency_limit
    testframework::section "Task file / Файл задач"; test_run_task_file
    testframework::section "FIFO / FIFO"; test_fifo_scheduler
    testframework::section "FIFO dependency / Зависимость FIFO"; test_fifo_requires_mkfifo
    testframework::section "FIFO task file / FIFO файл задач"; test_fifo_task_file
    testframework::section "FIFO burst / FIFO серия"; test_fifo_burst_completion
    testframework::section "xargs stub / Заглушка xargs"; test_xargs_stub
    testframework::section "Empty input / Пустой вход"; test_empty_and_clean_output
    testframework::section "Empty read-only / Пустой read-only"; test_empty_read_only_directory
    testframework::section "Special items / Особые элементы"; test_special_items
    testframework::section "Callback exit/exec / Выход callback"; test_callback_exit_exec
    testframework::section "Cancellation / Отмена"; test_cancel_cleans_workers
    testframework::section "Programmatic cancel / Программная отмена"; test_programmatic_cancel
    testframework::section "Persistence failures / Ошибки записи"; test_result_persistence_failures
    testframework::section "Result symlinks / Symlink результатов"; test_result_symlinks_replaced
    testframework::section "Publication race / Гонка публикации"; test_publication_race
    testframework::section "Signal restoration / Восстановление сигналов"; test_signal_handlers_restored
    testframework::section "Option-like out-dir / Каталог с дефисом"; test_option_like_output_directory
    testframework::summary
}

main "$@"
