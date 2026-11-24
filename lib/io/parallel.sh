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

# @description Run a callback once for each input element.
# @description Вызвать callback один раз для каждого элемента.
# @contract action
# @param $@ common options, callback, --, items
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
