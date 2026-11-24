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
# @global IO_PARALLEL_PIDS — Parallel: active worker PIDs (category: state)
# @global IO_PARALLEL_PIDS — Parallel: PID активных воркеров (category: state)
declare -ga IO_PARALLEL_PIDS=()
# @global IO_PARALLEL_INDICES — Parallel: active task indices (category: state)
# @global IO_PARALLEL_INDICES — Parallel: индексы активных задач (category: state)
declare -ga IO_PARALLEL_INDICES=()
# @global IO_PARALLEL_FAILED — Parallel: aggregate failure flag (category: state)
# @global IO_PARALLEL_FAILED — Parallel: флаг общей ошибки (category: state)
declare -g IO_PARALLEL_FAILED=0
# @global IO_PARALLEL_TEMP — Parallel: internal temporary directory (category: state)
# @global IO_PARALLEL_TEMP — Parallel: внутренний временный каталог (category: state)
declare -g IO_PARALLEL_TEMP=""
# @global IO_PARALLEL_FD — Parallel: FIFO completion descriptor (category: state)
# @global IO_PARALLEL_FD — Parallel: дескриптор FIFO завершений (category: state)
declare -g IO_PARALLEL_FD=""

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
    if [[ ! "$IO_PARALLEL_JOBS" =~ ^[1-9][0-9]*$ ]]; then
        bs_log_error "io::parallel: --jobs must be a positive integer"
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

# @description Run a callback once for each input element.
# @description Вызвать callback один раз для каждого элемента.
# @contract action
# @param $@ common options, --, callback, items
# @returns E_SUCCESS, E_INVALID or E_ERROR
io::parallel::map() {
    io::parallel::__parse "$@" || return $?
    (( ${#IO_PARALLEL_ARGS[@]} >= 1 )) || {
        bs_log_error "io::parallel::map: callback required"
        return "${E_INVALID:-2}"
    }
    local callback="${IO_PARALLEL_ARGS[0]}"
    local -a items=("${IO_PARALLEL_ARGS[@]:1}")
    mkdir -p "$IO_PARALLEL_OUT" || return "${E_ERROR:-1}"
    case "$IO_PARALLEL_SCHED" in
        pid)  io::parallel::__pid_map "$callback" "${items[@]}" ;;
        fifo) io::parallel::__fifo_map "$callback" "${items[@]}" ;;
        xargs) return "${E_INVALID:-2}" ;;
    esac
}

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
# @param $@ groups: count index command args...
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

# @description Run one shell command per non-comment line of a task file.
# @description Выполнить одну shell-команду на строку файла задач.
# @contract action
# @param $@ common options, --, task-file
# @returns E_SUCCESS, E_INVALID or E_ERROR
io::parallel::run() {
    io::parallel::__parse "$@" || return $?
    (( ${#IO_PARALLEL_ARGS[@]} == 1 )) || {
        bs_log_error "io::parallel::run: exactly one task file is required"
        return "${E_INVALID:-2}"
    }
    local file="${IO_PARALLEL_ARGS[0]}" line=""
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
    case "$IO_PARALLEL_SCHED" in
        pid)  io::parallel::__pid_tasks "${tasks[@]}" ;;
        fifo) io::parallel::__fifo_tasks "${tasks[@]}" ;;
        xargs) return "${E_INVALID:-2}" ;;
    esac
}
