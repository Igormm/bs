# io::parallel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `lib/io/parallel.sh`, a `@shell bash4,zsh` module that runs callback maps or task files with bounded parallelism and file-based results.

**Architecture:** One public module owns argument parsing, result naming and cleanup. Two private scheduler implementations (`pid`, `fifo`) share the same worker wrapper and `.out`/`.err`/`.rc` contract. The default `pid` scheduler uses only shell builtins; `fifo` requires `mkfifo`. The recognized `xargs` option is an explicit non-implemented stub.

**Tech Stack:** Bash 4.2+, zsh 5.9, BS loader, `core/args`, `core/const`, `core/logger`, `core/utils`, `core/errorhandler`, POSIX terminal tools (`mktemp`, `mkdir`, `cat`, `chmod`), optional `mkfifo`.

**Spec:** `docs/superpowers/specs/2026-11-24-io-parallel-design.md`

## Global Constraints

- Module header: `#!/usr/bin/env bs`, `# shellcheck shell=bash`, `# @shell bash4,zsh — …`.
- zsh compatibility shim: `setopt KSH_ARRAYS SH_WORD_SPLIT no_nomatch`.
- Forbidden: `local -n`, `printf -v`, `mapfile`, `wait -n`, `${!array[@]}`.
- Functions never call `exit`; invalid input returns `E_INVALID`, runtime failure returns `E_ERROR`.
- `map`/`run` write nothing to stdout; results go to `<out-dir>/NNNN.out`, `.err`, `.rc`.
- All tasks run even when one worker fails; aggregate status is `E_ERROR` if any `.rc` is non-zero.
- `map` passes one input element as one argument to the callback.
- `run` executes each non-empty, non-comment line through `bash -c`.
- `--` ends option parsing exactly once.
- `pid` is the default scheduler and has no external dependency beyond coreutils.
- `fifo` requires `mkfifo`.
- `xargs` is recognized but returns `E_ERROR` without starting processes or creating results.
- Every public function has a bilingual DocBlock with `@contract`, `@param`, `@returns`, and `@stdout` when applicable.
- Module-level variables carry bilingual `# @global` snippets.

## Review Focus

- Elements containing spaces, tabs and newlines survive `map` unchanged.
- No more than `--jobs` workers run concurrently, including during slot reuse.
- A failing worker does not stop later workers and produces its own non-zero `.rc`.
- Missing `mkfifo` returns `E_ERROR` without orphan workers or stale internal temp files.
- The `xargs` stub returns `E_ERROR` without processes, result files or temp state.
- SIGINT/SIGTERM kills active workers, waits for them and removes internal temp state while preserving `out-dir`.

---

### Task 1: Module skeleton, parser and result naming

**Files:**
- Create: `lib/io/parallel.sh`
- Create: `tests/unit/testparallelunit.sh`

**Interfaces:**
- Consumes: `bs_guard`, `bs_source_relative`, `bs_args_reset`, `bs_args_flag`, `bs_args_parse`, `bs_args_flag_get`, `bs_arr_to_args`, `E_SUCCESS`, `E_INVALID`, `E_ERROR`.
- Produces: `io::parallel::__parse`, `io::parallel::__result_name`, `io::parallel::map`, `io::parallel::run` stubs, globals `IO_PARALLEL_JOBS`, `IO_PARALLEL_OUT`, `IO_PARALLEL_SCHED`, `IO_PARALLEL_ARGS`.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/testparallelunit.sh`:

```bash
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
        out="$(probe "$sh_bin" -- 'io::parallel::map --jobs 0 --out-dir "$HOME/r" -- true a')" || rc=$?
        testframework::assert_equal "2" "$rc" "${sh_bin}: zero jobs returns E_INVALID"
        rc=0
        out="$(probe "$sh_bin" -- 'io::parallel::map --jobs 2 --out-dir "$HOME/r" --scheduler bad -- true a')" || rc=$?
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
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `./bs run tests/unit/testparallelunit.sh`

Expected: FAIL because `lib/io/parallel.sh` does not exist.

- [ ] **Step 3: Create the module skeleton and parser**

Create `lib/io/parallel.sh`:

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4,zsh — arrays and job control; zsh uses KSH_ARRAYS/SH_WORD_SPLIT
# lib/io/parallel.sh — bounded parallel map and task-file execution
# lib/io/parallel.sh — ограниченный параллельный map и запуск файла задач
#
# @depends core/args, core/const, core/logger, core/utils, core/errorhandler

bs::guard "IO_PARALLEL" || return 0
bs::source_relative "../../core/args.sh" "../../core/const.sh" \
    "../../core/logger.sh" "../../core/utils.sh" "../../core/errorhandler.sh"

if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt KSH_ARRAYS SH_WORD_SPLIT no_nomatch
fi

# @global IO_PARALLEL_VERSION — Module version (category: module-flag)
# @global IO_PARALLEL_VERSION — Версия модуля (category: module-flag)
declare -g IO_PARALLEL_VERSION="1.0.0"
# @global IO_PARALLEL_LOADED — Module loaded flag (category: module-flag)
# @global IO_PARALLEL_LOADED — Флаг загрузки модуля (category: module-flag)
declare -g IO_PARALLEL_LOADED="1"

# @global IO_PARALLEL_JOBS — Parallel: worker limit (category: state)
# @global IO_PARALLEL_JOBS — Parallel: лимит воркеров (category: state)
declare -g IO_PARALLEL_JOBS=""
# @global IO_PARALLEL_OUT — Parallel: result directory (category: state)
# @global IO_PARALLEL_OUT — Parallel: каталог результатов (category: state)
declare -g IO_PARALLEL_OUT=""
# @global IO_PARALLEL_SCHED — Parallel: scheduler name (category: state)
# @global IO_PARALLEL_SCHED — Parallel: имя планировщика (category: state)
declare -g IO_PARALLEL_SCHED="pid"
# @global IO_PARALLEL_ARGS — Parallel: parsed positional arguments (category: state)
# @global IO_PARALLEL_ARGS — Parallel: позиционные аргументы (category: state)
declare -ga IO_PARALLEL_ARGS=()

# @private
# @description Parse common options without exiting the caller.
# @description Разобрать общие опции без выхода из вызывающего скрипта.
# @param $@ options and positional arguments
# @returns E_SUCCESS or E_INVALID
io::parallel::__parse() {
    bs_args_reset
    bs_args_flag jobs value "" number
    bs_args_flag out-dir value "" ""
    bs_args_flag scheduler value pid enum:pid,fifo,xargs
    bs_args_flag_describe jobs "worker limit / лимит воркеров"
    bs_args_flag_describe out-dir "result directory / каталог результатов"
    bs_args_flag_describe scheduler "pid|fifo|xargs"
    bs_args_parse "$@" || return "${E_INVALID:-2}"

    IO_PARALLEL_JOBS="$(bs_args_flag_get jobs)"
    IO_PARALLEL_OUT="$(bs_args_flag_get out-dir)"
    IO_PARALLEL_SCHED="$(bs_args_flag_get scheduler)"
    if [[ -z "$IO_PARALLEL_JOBS" || -z "$IO_PARALLEL_OUT" ]]; then
        bs_log_error "io::parallel: --jobs and --out-dir are required"
        return "${E_INVALID:-2}"
    fi
    eval "$(bs_arr_to_args bs_args_rest)"
    IO_PARALLEL_ARGS=("$@")
    return "${E_SUCCESS:-0}"
}

# @private
# @description Format a zero-based result index.
# @description Отформатировать индекс результата с нуля.
# @param $1 index
# @stdout zero-padded index
io::parallel::__result_name() {
    printf '%04d' "$1"
}

# @description Run a callback once for each input element.
# @description Вызвать callback один раз для каждого элемента.
# @contract action
# @param $@ common options, --, callback, items
# @returns E_SUCCESS, E_INVALID or E_ERROR
io::parallel::map() {
    io::parallel::__parse "$@" || return $?
    return "${E_INVALID:-2}"
}

# @description Run one shell command per non-comment line of a task file.
# @description Выполнить одну shell-команду на строку файла задач.
# @contract action
# @param $@ common options, --, task-file
# @returns E_SUCCESS, E_INVALID or E_ERROR
io::parallel::run() {
    io::parallel::__parse "$@" || return $?
    return "${E_INVALID:-2}"
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `./bs run tests/unit/testparallelunit.sh`

Expected: PASS in bash and zsh.

- [ ] **Step 5: Commit**

```bash
git add lib/io/parallel.sh tests/unit/testparallelunit.sh
git commit -m "feat(io): scaffold io::parallel parser and result contract"
```

---

### Task 2: Worker wrapper and default PID scheduler for `map`

**Files:**
- Modify: `lib/io/parallel.sh`
- Modify: `tests/unit/testparallelunit.sh`

**Interfaces:**
- Consumes: Task 1 globals and parser.
- Produces: `io::parallel::__worker`, `io::parallel::__pid_start`, `io::parallel::__pid_reap_one`, `io::parallel::__pid_map`, globals `IO_PARALLEL_PIDS`, `IO_PARALLEL_INDICES`, `IO_PARALLEL_FAILED`.

- [ ] **Step 1: Add failing tests for output separation, ordering, concurrency and failure aggregation**

Append to `tests/unit/testparallelunit.sh`:

```bash
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
                printf "start %s\n" "$$" >> "$IO_PARALLEL_OUT/events"
                sleep 0.05
                printf "end %s\n" "$$" >> "$IO_PARALLEL_OUT/events"
            }
            io::parallel::map --jobs 2 --out-dir "$1" -- slow_worker a b c d e
        ' _ "$out_dir")" || rc=$?
        testframework::assert_equal "0" "$rc" "${sh_bin}: bounded map succeeds"
        testframework::assert_equal "2" \
            "$(awk '\''$1=="start"{n++; if(n>m)m=n} $1=="end"{n--} END{print m}'\'' "$out_dir/events")" \
            "${sh_bin}: concurrency never exceeds jobs"
        rc=0
    done
}
```

Add the calls in `main`:

```bash
testframework::section "PID map / PID map"; test_pid_map_contract
testframework::section "Concurrency / Параллелизм"; test_pid_map_concurrency_limit
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `./bs run tests/unit/testparallelunit.sh`

Expected: FAIL because `map` still returns `E_INVALID`.

- [ ] **Step 3: Implement the worker and PID scheduler**

Add these globals to `lib/io/parallel.sh`:

```bash
# @global IO_PARALLEL_PIDS — Parallel: active worker PIDs (category: state)
# @global IO_PARALLEL_PIDS — Parallel: PID активных воркеров (category: state)
declare -ga IO_PARALLEL_PIDS=()
# @global IO_PARALLEL_INDICES — Parallel: active task indices (category: state)
# @global IO_PARALLEL_INDICES — Parallel: индексы активных задач (category: state)
declare -ga IO_PARALLEL_INDICES=()
# @global IO_PARALLEL_FAILED — Parallel: aggregate failure flag (category: state)
# @global IO_PARALLEL_FAILED — Parallel: флаг общей ошибки (category: state)
declare -g IO_PARALLEL_FAILED=0
```

Add the private implementation:

```bash
# @private
# @description Execute one worker and persist stdout, stderr and status.
# @description Выполнить воркер и сохранить stdout, stderr и статус.
# @param $1 index
# @param $2 output directory
# @param $@ command and arguments
# @returns always E_SUCCESS; worker status is written to NNNN.rc
io::parallel::__worker() {
    local idx="$1" out="$2"; shift 2
    local name rc=0
    name="$(io::parallel::__result_name "$idx")"
    "$@" > "$out/$name.out" 2> "$out/$name.err" || rc=$?
    printf '%s\n' "$rc" > "$out/$name.rc"
    return "${E_SUCCESS:-0}"
}

# @private
# @description Start one PID-pool worker.
# @description Запустить одного воркера PID-pool.
# @param $1 index
# @param $@ command and arguments
io::parallel::__pid_start() {
    local idx="$1"; shift
    io::parallel::__worker "$idx" "$IO_PARALLEL_OUT" "$@" &
    IO_PARALLEL_PIDS+=("$!")
    IO_PARALLEL_INDICES+=("$idx")
}

# @private
# @description Reap the oldest active PID and aggregate its status.
# @description Дождаться самого раннего PID и учесть его статус.
io::parallel::__pid_reap_one() {
    local pid="${IO_PARALLEL_PIDS[0]}" idx="${IO_PARALLEL_INDICES[0]}"
    local name rc
    wait "$pid" || true
    name="$(io::parallel::__result_name "$idx")"
    rc="$(cat "$IO_PARALLEL_OUT/$name.rc")"
    [[ "$rc" -eq 0 ]] || IO_PARALLEL_FAILED=1
    IO_PARALLEL_PIDS=("${IO_PARALLEL_PIDS[@]:1}")
    IO_PARALLEL_INDICES=("${IO_PARALLEL_INDICES[@]:1}")
}

# @private
# @description Run callback for every item with the PID scheduler.
# @description Вызвать callback для каждого элемента через PID scheduler.
# @param $1 callback
# @param $@ items
# @returns E_SUCCESS or E_ERROR
io::parallel::__pid_map() {
    local callback="$1"; shift
    local idx=0 item
    IO_PARALLEL_PIDS=(); IO_PARALLEL_INDICES=(); IO_PARALLEL_FAILED=0
    for item in "$@"; do
        while (( ${#IO_PARALLEL_PIDS[@]} >= IO_PARALLEL_JOBS )); do
            io::parallel::__pid_reap_one
        done
        io::parallel::__pid_start "$idx" "$callback" "$item"
        idx=$(( idx + 1 ))
    done
    while (( ${#IO_PARALLEL_PIDS[@]} > 0 )); do
        io::parallel::__pid_reap_one
    done
    (( IO_PARALLEL_FAILED == 0 )) || return "${E_ERROR:-1}"
    return "${E_SUCCESS:-0}"
}
```

Replace the `map` stub:

```bash
io::parallel::map() {
    io::parallel::__parse "$@" || return $?
    (( ${#IO_PARALLEL_ARGS[@]} >= 1 )) || {
        bs_log_error "io::parallel::map: callback required"
        return "${E_INVALID:-2}"
    }
    local callback="${IO_PARALLEL_ARGS[0]}"
    local -a items=("${IO_PARALLEL_ARGS[@]:1}")
    mkdir -p "$IO_PARALLEL_OUT" || return "${E_ERROR:-1}"
    io::parallel::__pid_map "$callback" "${items[@]}"
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `./bs run tests/unit/testparallelunit.sh`

Expected: PASS in bash and zsh.

- [ ] **Step 5: Commit**

```bash
git add lib/io/parallel.sh tests/unit/testparallelunit.sh
git commit -m "feat(io): add PID scheduler for parallel map"
```

---

### Task 3: Task-file runner

**Files:**
- Modify: `lib/io/parallel.sh`
- Modify: `tests/unit/testparallelunit.sh`

**Interfaces:**
- Consumes: Task 2 worker and PID scheduler.
- Produces: `io::parallel::__pid_tasks`, functional `io::parallel::run`.

- [ ] **Step 1: Add a failing task-file test**

Append:

```bash
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
```

Add the call in `main`.

- [ ] **Step 2: Run and verify failure**

Run: `./bs run tests/unit/testparallelunit.sh`

Expected: FAIL because `run` is still a stub.

- [ ] **Step 3: Implement task-file execution**

Add:

```bash
# @private
# @description Run task strings through the PID scheduler.
# @description Выполнить строки задач через PID scheduler.
# @param $@ task strings
# @returns E_SUCCESS or E_ERROR
io::parallel::__pid_tasks() {
    local idx=0 task
    IO_PARALLEL_PIDS=(); IO_PARALLEL_INDICES=(); IO_PARALLEL_FAILED=0
    for task in "$@"; do
        while (( ${#IO_PARALLEL_PIDS[@]} >= IO_PARALLEL_JOBS )); do
            io::parallel::__pid_reap_one
        done
        io::parallel::__pid_start "$idx" bash -c "$task"
        idx=$(( idx + 1 ))
    done
    while (( ${#IO_PARALLEL_PIDS[@]} > 0 )); do
        io::parallel::__pid_reap_one
    done
    (( IO_PARALLEL_FAILED == 0 )) || return "${E_ERROR:-1}"
    return "${E_SUCCESS:-0}"
}
```

Replace `run`:

```bash
io::parallel::run() {
    io::parallel::__parse "$@" || return $?
    (( ${#IO_PARALLEL_ARGS[@]} == 1 )) || {
        bs_log_error "io::parallel::run: exactly one task file is required"
        return "${E_INVALID:-2}"
    }
    local file="${IO_PARALLEL_ARGS[0]}" line
    [[ -r "$file" ]] || {
        bs_log_error "io::parallel::run: task file is not readable: $file"
        return "${E_INVALID:-2}"
    }
    local -a tasks=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        tasks+=("$line")
    done < "$file"
    mkdir -p "$IO_PARALLEL_OUT" || return "${E_ERROR:-1}"
    io::parallel::__pid_tasks "${tasks[@]}"
}
```

- [ ] **Step 4: Run and verify pass**

Run: `./bs run tests/unit/testparallelunit.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/io/parallel.sh tests/unit/testparallelunit.sh
git commit -m "feat(io): add parallel task-file runner"
```

---

### Task 4: FIFO scheduler

**Files:**
- Modify: `lib/io/parallel.sh`
- Modify: `tests/unit/testparallelunit.sh`

**Interfaces:**
- Consumes: Task 2 worker wrapper and result contract.
- Produces: `io::parallel::__fifo_map`, `io::parallel::__fifo_tasks`, `IO_PARALLEL_TEMP`.

- [ ] **Step 1: Add failing FIFO tests**

Append a helper that runs the same contract with `--scheduler fifo`:

```bash
test_fifo_scheduler() {
    local sh_bin out_dir rc=0
    for sh_bin in bash zsh; do
        out_dir="$T/${sh_bin}-fifo"
        probe "$sh_bin" -- '
            fifo_worker() { printf "out:%s\n" "$1"; printf "err:%s\n" "$1" >&2; [[ "$1" != bad ]]; }
            io::parallel::map --jobs 2 --scheduler fifo --out-dir "$1" -- \
                fifo_worker first bad third
            printf "aggregate=%s\n" "$?"
        ' _ "$out_dir" >/dev/null || rc=$?
        testframework::assert_equal "0" "$rc" "${sh_bin}: fifo map does not exit the caller"
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
```

Also add `test_fifo_task_file`: use a `mkfifo` wrapper that records its call,
write two valid task lines with a quoted heredoc, invoke
`io::parallel::run --jobs 2 --scheduler fifo --out-dir "$1" -- "$2"`, and assert
`0000.out`, `0001.err`, both zero statuses and the wrapper marker in bash and zsh.
This pins the distinct FIFO task group (`3 idx bash -c task`) rather than only the
map group (`2 idx callback item`).

Add `test_fifo_burst_completion`: run 64 immediate `true` callbacks with
`--jobs 64` in bash and zsh, assert success and 64 `.rc` files. This reproduces a
real FIFO race: reopening the queue for each completion can pair one reader with
many blocked writers, causing the other writers to receive `SIGPIPE` and leaving
the parent waiting for messages that will never arrive.

Create `$T/home/no-tools` in `main` before the tests.

- [ ] **Step 2: Run and verify failure**

Run: `./bs run tests/unit/testparallelunit.sh`

Expected: FAIL because `fifo` is not dispatched.

- [ ] **Step 3: Implement FIFO scheduling**

Add the temp-state global:

```bash
# @global IO_PARALLEL_TEMP — Parallel: internal temporary directory (category: state)
# @global IO_PARALLEL_TEMP — Parallel: внутренний временный каталог (category: state)
declare -g IO_PARALLEL_TEMP=""
# @global IO_PARALLEL_FD — Parallel: FIFO completion descriptor (category: state)
# @global IO_PARALLEL_FD — Parallel: дескриптор FIFO завершений (category: state)
declare -g IO_PARALLEL_FD=""
```

Add a FIFO cleanup helper and a generic FIFO runner. The parent opens the FIFO
read-write once and keeps that descriptor for the whole pool; reopening it for
each completion is the burst race described above.

```bash
# @private
# @description Close the FIFO descriptor and remove scheduler temporary state.
# @description Закрыть дескриптор FIFO и удалить временное состояние планировщика.
io::parallel::__fifo_cleanup() {
    if [[ -n "$IO_PARALLEL_FD" ]]; then
        exec {IO_PARALLEL_FD}>&-
        IO_PARALLEL_FD=""
    fi
    [[ -z "$IO_PARALLEL_TEMP" ]] || utils::ignore rm -rf "$IO_PARALLEL_TEMP"
    IO_PARALLEL_TEMP=""
}

# @private
# @description Run argv groups through a FIFO completion queue.
# @description Выполнить группы argv через FIFO завершений.
# @param $@ groups: index command args...
# @returns E_SUCCESS or E_ERROR
io::parallel::__fifo_run() {
    utils::has mkfifo || {
        bs_log_error "io::parallel: scheduler fifo requires mkfifo"
        return "${E_ERROR:-1}"
    }
    IO_PARALLEL_TEMP="$(mktemp -d)" || return "${E_ERROR:-1}"
    local fifo="$IO_PARALLEL_TEMP/done"
    mkfifo "$fifo" || { io::parallel::__fifo_cleanup; return "${E_ERROR:-1}"; }
    exec {IO_PARALLEL_FD}<>"$fifo" || { io::parallel::__fifo_cleanup; return "${E_ERROR:-1}"; }

    IO_PARALLEL_PIDS=(); IO_PARALLEL_INDICES=(); IO_PARALLEL_FAILED=0
    while (( $# > 0 )); do
        local count="$1" idx="$2"; shift 2
        local -a cmd=("${@:1:$count}")
        while (( ${#IO_PARALLEL_PIDS[@]} >= IO_PARALLEL_JOBS )); do
            local done_idx pid found=0 j
            IFS= read -r done_idx <&"$IO_PARALLEL_FD"
            for (( j=0; j<${#IO_PARALLEL_PIDS[@]}; j++ )); do
                if [[ "${IO_PARALLEL_INDICES[$j]}" == "$done_idx" ]]; then
                    pid="${IO_PARALLEL_PIDS[$j]}"; found=1
                    wait "$pid" || true
                    local name rc
                    name="$(io::parallel::__result_name "$done_idx")"
                    rc="$(cat "$IO_PARALLEL_OUT/$name.rc")"
                    [[ "$rc" -eq 0 ]] || IO_PARALLEL_FAILED=1
                    IO_PARALLEL_PIDS=("${IO_PARALLEL_PIDS[@]:0:$j}" "${IO_PARALLEL_PIDS[@]:$((j+1))}")
                    IO_PARALLEL_INDICES=("${IO_PARALLEL_INDICES[@]:0:$j}" "${IO_PARALLEL_INDICES[@]:$((j+1))}")
                    break
                fi
            done
            (( found == 1 )) || { io::parallel::__fifo_cleanup; return "${E_ERROR:-1}"; }
        done
        (
            io::parallel::__worker "$idx" "$IO_PARALLEL_OUT" "${cmd[@]}"
            printf '%s\n' "$idx" > "$fifo"
        ) &
        IO_PARALLEL_PIDS+=("$!"); IO_PARALLEL_INDICES+=("$idx")
        shift "$count"
    done

    while (( ${#IO_PARALLEL_PIDS[@]} > 0 )); do
        local done_idx pid found=0 j
        IFS= read -r done_idx <&"$IO_PARALLEL_FD"
        for (( j=0; j<${#IO_PARALLEL_PIDS[@]}; j++ )); do
            if [[ "${IO_PARALLEL_INDICES[$j]}" == "$done_idx" ]]; then
                pid="${IO_PARALLEL_PIDS[$j]}"; found=1
                wait "$pid" || true
                local name rc
                name="$(io::parallel::__result_name "$done_idx")"
                rc="$(cat "$IO_PARALLEL_OUT/$name.rc")"
                [[ "$rc" -eq 0 ]] || IO_PARALLEL_FAILED=1
                IO_PARALLEL_PIDS=("${IO_PARALLEL_PIDS[@]:0:$j}" "${IO_PARALLEL_PIDS[@]:$((j+1))}")
                IO_PARALLEL_INDICES=("${IO_PARALLEL_INDICES[@]:0:$j}" "${IO_PARALLEL_INDICES[@]:$((j+1))}")
                break
            fi
        done
        (( found == 1 )) || { io::parallel::__fifo_cleanup; return "${E_ERROR:-1}"; }
    done
    io::parallel::__fifo_cleanup
    (( IO_PARALLEL_FAILED == 0 )) || return "${E_ERROR:-1}"
    return "${E_SUCCESS:-0}"
}

io::parallel::__fifo_map() {
    local callback="$1"; shift
    local -a groups=()
    local idx=0 item
    for item in "$@"; do
        groups+=(2 "$idx" "$callback" "$item")
        idx=$(( idx + 1 ))
    done
    io::parallel::__fifo_run "${groups[@]}"
}

io::parallel::__fifo_tasks() {
    local -a groups=()
    local idx=0 task
    for task in "$@"; do
        groups+=(3 "$idx" bash -c "$task")
        idx=$(( idx + 1 ))
    done
    io::parallel::__fifo_run "${groups[@]}"
}
```

Dispatch in `map` and `run`:

```bash
case "$IO_PARALLEL_SCHED" in
    pid)  io::parallel::__pid_map "$callback" "${items[@]}" ;;
    fifo) io::parallel::__fifo_map "$callback" "${items[@]}" ;;
    xargs) return "${E_INVALID:-2}" ;;
esac
```

For `run`, add `fifo) io::parallel::__fifo_tasks "${tasks[@]}" ;;`.

- [ ] **Step 4: Run and verify pass**

Run: `./bs run tests/unit/testparallelunit.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/io/parallel.sh tests/unit/testparallelunit.sh
git commit -m "feat(io): add FIFO completion scheduler"
```

---

### Task 5: `xargs` scheduler stub

**Files:**
- Modify: `lib/io/parallel.sh`
- Modify: `tests/unit/testparallelunit.sh`

**Interfaces:**
- Consumes: Task 1 parser and Task 3 task list.
- Produces: `io::parallel::__xargs_map`, `io::parallel::__xargs_tasks`; both return `E_ERROR` without side effects.

- [ ] **Step 1: Add a failing stub test**

Append:

```bash
test_xargs_stub() {
    local sh_bin out_dir tasks rc=0
    for sh_bin in bash zsh; do
        out_dir="$T/${sh_bin}-xargs-stub"
        rc=0
        probe "$sh_bin" -- '
            io::parallel::map --jobs 2 --scheduler xargs --out-dir "$1" -- true first
        ' _ "$out_dir" >/dev/null || rc=$?
        testframework::assert_equal "1" "$rc" "${sh_bin}: xargs map returns E_ERROR"
        testframework::assert_false "-e '$out_dir'" "${sh_bin}: xargs stub creates no result directory"

        tasks="$T/${sh_bin}-xargs-stub-tasks.txt"
        cat > "$tasks" <<'TASKS'
printf 'one\n'
TASKS
        out_dir="$T/${sh_bin}-xargs-stub-tasks"
        rc=0
        probe "$sh_bin" -- '
            io::parallel::run --jobs 2 --scheduler xargs --out-dir "$1" -- "$2"
        ' _ "$out_dir" "$tasks" >/dev/null || rc=$?
        testframework::assert_equal "1" "$rc" "${sh_bin}: xargs run returns E_ERROR"
        testframework::assert_false "-e '$out_dir'" "${sh_bin}: xargs stub creates no task results"
        rc=0
    done
}
```

Add the call in `main`.

- [ ] **Step 2: Run and verify failure**

Run: `./bs run tests/unit/testparallelunit.sh`

Expected: FAIL because `xargs` currently returns `E_INVALID` and may create `out-dir` before dispatch.

- [ ] **Step 3: Implement only the stub**

Add:

```bash
# @private
# @description Reserved xargs scheduler stub; intentionally not implemented.
# @description Заглушка xargs scheduler; намеренно не реализована.
# @param $1 callback
# @param $@ items
# @returns E_ERROR
io::parallel::__xargs_map() {
    bs_log_error "io::parallel: scheduler xargs is not implemented"
    return "${E_ERROR:-1}"
}

# @private
# @description Reserved xargs task scheduler stub; intentionally not implemented.
# @description Заглушка xargs task scheduler; намеренно не реализована.
# @param $@ task strings
# @returns E_ERROR
io::parallel::__xargs_tasks() {
    bs_log_error "io::parallel: scheduler xargs is not implemented"
    return "${E_ERROR:-1}"
}
```

In `map`, dispatch before `mkdir -p`:

```bash
if [[ "$IO_PARALLEL_SCHED" == "xargs" ]]; then
    io::parallel::__xargs_map "$callback" "${items[@]}" || return $?
    return "${E_SUCCESS:-0}"
fi
mkdir -p "$IO_PARALLEL_OUT" || return "${E_ERROR:-1}"
```

In `run`, dispatch after reading and validating the task file but before
`mkdir -p`:

```bash
if [[ "$IO_PARALLEL_SCHED" == "xargs" ]]; then
    io::parallel::__xargs_tasks "${tasks[@]}" || return $?
    return "${E_SUCCESS:-0}"
fi
mkdir -p "$IO_PARALLEL_OUT" || return "${E_ERROR:-1}"
```

The remaining scheduler branches are only `pid` and `fifo`.

- [ ] **Step 4: Run and verify pass**

Run: `./bs run tests/unit/testparallelunit.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/io/parallel.sh tests/unit/testparallelunit.sh
git commit -m "chore(io): reserve xargs scheduler stub"
```

---

### Task 6: Cancellation and internal cleanup

**Files:**
- Modify: `lib/io/parallel.sh`
- Modify: `tests/unit/testparallelunit.sh`

**Interfaces:**
- Consumes: `IO_PARALLEL_PIDS`, `IO_PARALLEL_TEMP`, `bs_signal_on`, `bs_signal_reset`.
- Produces: `io::parallel::cancel`, `io::parallel::__cancel_handler`, `io::parallel::__cleanup`.

- [ ] **Step 1: Add a failing cancellation test**

Append:

```bash
test_cancel_cleans_workers() {
    local sh_bin marker="$T/cancelled" rc=0
    for sh_bin in bash zsh; do
        rm -f "$marker"
        rc=0
        probe "$sh_bin" -- '
            slow_task() { sleep 5; printf "leaked\n" > "$1"; }
            io::parallel::map --jobs 1 --out-dir "$HOME/r" -- slow_task "$1" &
            pool_pid=$!
            sleep 0.1
            kill -TERM "$pool_pid"
            wait "$pool_pid" || true
        ' _ "$marker" >/dev/null || rc=$?
        sleep 0.2
        testframework::assert_false "test -f '$marker'" "${sh_bin}: SIGTERM prevents worker side effects"
        rc=0
    done
}
```

- [ ] **Step 2: Run and verify failure**

Run: `./bs run tests/unit/testparallelunit.sh`

Expected: FAIL because the worker survives SIGTERM.

- [ ] **Step 3: Implement cancellation**

Add:

```bash
# @private
# @description Stop workers and remove internal temporary state without changing
# the aggregate result. / Остановить воркеров и удалить временное состояние,
# не меняя общий результат.
io::parallel::__stop_workers() {
    local pid
    for pid in "${IO_PARALLEL_PIDS[@]}"; do
        [[ "$pid" =~ ^[1-9][0-9]*$ ]] && kill -TERM "$pid" 2>/dev/null || true
    done
    for pid in "${IO_PARALLEL_PIDS[@]}"; do
        [[ "$pid" =~ ^[1-9][0-9]*$ ]] && wait "$pid" 2>/dev/null || true
    done
    IO_PARALLEL_PIDS=(); IO_PARALLEL_INDICES=()
    io::parallel::__fifo_cleanup
}

# @description Cancel active workers and remove internal temporary state.
# @description Отменить активных воркеров и удалить внутреннее временное состояние.
# @contract action
# @returns E_SUCCESS
io::parallel::cancel() {
    io::parallel::__stop_workers
    IO_PARALLEL_FAILED=1
    return "${E_SUCCESS:-0}"
}

# @private
# @description Signal handler used during an active pool.
# @description Обработчик сигнала для активного пула.
io::parallel::__cancel_handler() {
    io::parallel::cancel
}

# @private
# @description Restore default signal behaviour and clean internal state.
# @description Вернуть сигналам поведение по умолчанию и очистить внутреннее состояние.
io::parallel::__cleanup() {
    bs_signal_reset INT
    bs_signal_reset TERM
    io::parallel::__stop_workers
}
```

At the start of `__pid_map`, `__pid_tasks` and `__fifo_run`, install handlers:

```bash
bs_signal_on INT io::parallel::__cancel_handler
bs_signal_on TERM io::parallel::__cancel_handler
```

Before every successful/error return, call:

```bash
io::parallel::__cleanup
```

- [ ] **Step 4: Run and verify pass**

Run: `./bs run tests/unit/testparallelunit.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/io/parallel.sh tests/unit/testparallelunit.sh
git commit -m "feat(io): cancel parallel workers on signals"
```

---

### Task 7: Example, documentation, registration and release

**Files:**
- Create: `examples/parallel_demo.sh`
- Modify: `documentation/en/07-testing/README.md`
- Modify: `documentation/ru/07-testing/README.md`
- Modify: `.agents/skills/README.md`
- Modify: `.agents/README.md`
- Modify: `AGENTS.md`
- Modify: `CHANGELOG.md`
- Modify: `core/version.sh`
- Modify: `documentation/en/02-core-concepts/architecture.md`
- Modify: `documentation/ru/02-core-concepts/architecture.md`
- Modify: `documentation/en/04-api-reference/core-api.md`
- Modify: `documentation/ru/04-api-reference/core-api.md`
- Modify: `tests/unit/testbsnobashunit.sh`
- Modify: `mtest/t_const_version.sh`
- Modify: `mtest/t_nu.nu`

**Interfaces:**
- Consumes: completed `io::parallel` module.
- Produces: runnable example, user documentation, skill catalog entry, release `0.26.0`.

- [ ] **Step 1: Add the example**

Create `examples/parallel_demo.sh`:

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
# examples/parallel_demo.sh — io::parallel in bash and zsh

set -euo pipefail

load "lib/io/parallel"

demo_worker() {
    printf 'item=%s pid=%s\n' "$1" "$$"
    printf 'diagnostic=%s\n' "$1" >&2
}

results="$(mktemp -d)"
trap 'rm -rf "$results"' EXIT

io::parallel::map --jobs 3 --out-dir "$results" -- \
    demo_worker -- alpha beta gamma delta

printf 'results: %s\n' "$results"
for rc_file in "$results"/*.rc; do
    printf '%s: rc=%s\n' "${rc_file##*/}" "$(cat "$rc_file")"
done
```

- [ ] **Step 2: Document the module in both testing guides**

Add to the full-suite section in both languages:

```markdown
### Parallel task execution / Параллельный запуск задач

`lib/io/parallel` runs callback maps or task files with a bounded worker pool.
Results are written as `NNNN.out`, `NNNN.err` and `NNNN.rc`; the function's
stdout stays clean.

```bash
load "lib/io/parallel"
io::parallel::map --jobs 4 --out-dir results -- my_worker item1 item2
io::parallel::run --jobs 4 --scheduler fifo --out-dir results -- tasks.txt
```

The module is `@shell bash4,zsh`. Schedulers: `pid` (default, no external
dependency), `fifo` (`mkfifo`), `xargs` (reserved stub, returns `E_ERROR`).
```

- [ ] **Step 3: Register the module in the skill/catalog indexes**

Add `bs-parallel` as a new `tier: bash4,zsh` skill? No: `io::parallel` is a
library module, not a workflow skill. Add it to the `lib/io` API documentation
only; do not create a skill entry.

Update `AGENTS.md` and both `.agents` catalogs only if a new
`bs-parallel` workflow skill is separately authored. This plan does not add
one.

- [ ] **Step 4: Bump the release to `0.26.0 "параллель"`**

Run the `bs-version-bump` procedure:

1. `core/version.sh`: `BS_VERSION="0.26.0"`, `BS_CODENAME="параллель"`.
2. `CHANGELOG.md`: add `## [0.26.0] - 2026-11-24 "параллель"` above `0.25.0`.
3. Replace `0.25.0` with `0.26.0` in en/ru architecture, en/ru core-api and
   `tests/unit/testbsnobashunit.sh`.
4. Replace codename `контракт` with `параллель` in `mtest/t_const_version.sh`
   and `mtest/t_nu.nu`.
5. Run `bash .agents/skills/bs-version-bump/scripts/version.sh check`.

CHANGELOG entry:

```markdown
### Added
- feat(io): `lib/io/parallel.sh` (`@shell bash4,zsh`) — bounded callback maps
  and task-file execution with `pid` and `fifo` schedulers; isolated
  `.out`/`.err`/`.rc` result files, aggregate failure status and signal cleanup.
  The `xargs` option is reserved as an explicit non-implemented stub.
```

- [ ] **Step 5: Run the example in both shells**

```bash
./bs run examples/parallel_demo.sh
zsh examples/parallel_demo.sh
```

Expected: both print four result files with `rc=0`.

- [ ] **Step 6: Run the full validation cycle**

```bash
bash tests/validatesyntax.sh
bash tests/validateshellcheck.sh
bash tests/runalltests.sh --jobs 8
bash tests/validatedocscode.sh
bash .agents/skills/bs-version-bump/scripts/version.sh check
```

Expected: all pass; only the two known environment skips may remain.

- [ ] **Step 7: Commit and push**

```bash
git add examples/parallel_demo.sh documentation/en/07-testing/README.md \
    documentation/ru/07-testing/README.md core/version.sh CHANGELOG.md \
    documentation/en/02-core-concepts/architecture.md \
    documentation/ru/02-core-concepts/architecture.md \
    documentation/en/04-api-reference/core-api.md \
    documentation/ru/04-api-reference/core-api.md \
    tests/unit/testbsnobashunit.sh mtest/t_const_version.sh mtest/t_nu.nu
git commit -m "chore(release): 0.26.0 \"параллель\""
git push origin main
```
