#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, eval с проверкой имён, trap; стек и обработчики — на слое core/data.sh / valid POSIX sh: case, eval with name checks, trap; the stack and the handlers are on the core/data.sh layer
# @tier core — builtins, tr and sleep; works everywhere
#
# errorhandler.sh — единый EXIT-хендлер и cleanup-хуки / unified EXIT handler and cleanup hooks
#
# @depends core/const, core/var, core/str, core/num, core/logger, core/data
#
# Идея / Idea:
# - любой модуль/скрипт может добавить очистку / any module/script can add cleanup:
#     cleanup::add my_cleanup_function
# - при завершении скрипта (даже при ошибке) cleanup выполнится / on script exit (even on
#   error) cleanup will execute
#
# ИМЕНА / NAMES
#   Real functions: bs_cleanup_add, bs_cleanup_run_all, bs_on_exit, bs_errorhandler_setup_trap,
#   bs_errorhandler_throw, bs_error_*, bs_signal_*, bs_exit, bs_function_exists; in bash and zsh also
#   the old names cleanup::add, error::exit, bs::exit, signal::on, function_exists, … (aliases).
#   Настоящие функции — bs_*; в bash и zsh — ещё и прежние имена (псевдонимы).
#
# ДАННЫЕ / DATA
#   The cleanup stack is the data-layer array bs_cleanup_stack (it was the bash array
#   BS_CLEANUP_STACK); the error handlers are the data-layer map bs_error_handlers (it was
#   the associative array __ERROR_HANDLERS).
#   Стек очистки — массив слоя данных bs_cleanup_stack (был массивом bash BS_CLEANUP_STACK);
#   обработчики ошибок — словарь слоя данных bs_error_handlers (был __ERROR_HANDLERS).

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# shellcheck disable=SC2154  # __bs_eh_fn присваивает bs_arr_pop через eval / __bs_eh_fn is assigned by bs_arr_pop through eval
bs_guard "ERRORHANDLER" || return 0

# Зависимости / Dependencies
bs_source_relative "const.sh" "var.sh" "str.sh" "num.sh" "logger.sh" "data.sh"

# ==========================================
# Очистка / Cleanup
# ==========================================

# @description Add cleanup function to stack / Добавить функцию очистки в стек
# @param $1 Function name to add to cleanup / Имя функции для добавления в очистку
# @example
#   cleanup::add my_cleanup_function
bs_cleanup_add() {
  if [ -z "${1-}" ]; then
    bs_log_warn "cleanup::add: не указана функция"
    return "${E_INVALID:-2}"
  fi
  bs_arr_push bs_cleanup_stack "$1"
}

# @private
# @description Run the cleanup functions, last added first, and empty the stack / Выполнить функции очистки, последняя добавленная — первой, и очистить стек
bs_cleanup_run_all() {
  while bs_arr_pop bs_cleanup_stack __bs_eh_fn; do
    "$__bs_eh_fn" || true
  done
  return 0
}

# @private
# @description The EXIT trap: runs the cleanup / Ловушка EXIT: выполняет очистку
bs_on_exit() {
  bs_cleanup_run_all
}

# @description Set the EXIT trap that runs the cleanup stack / Поставить ловушку EXIT, выполняющую стек очистки
bs_errorhandler_setup_trap() {
  trap 'bs_on_exit' EXIT
}

# ==========================================
# Ошибки / Errors
# ==========================================

# @description Report an error from a function and return its code / Сообщить об ошибке из функции и вернуть её код
# @param $1 function name / имя функции
# @param $2 message / сообщение
# @param $3 code, default E_ERROR / код, по умолчанию E_ERROR
bs_errorhandler_throw() {
  __bs_eh_func=${1:-unknown}
  __bs_eh_msg=${2:-}
  __bs_eh_code=${3:-${E_ERROR:-1}}
  if command -v bs_log_error >/dev/null 2>&1; then
    bs_log_error "[${__bs_eh_func}] ${__bs_eh_msg}"
  else
    printf 'ERROR [%s] %s\n' "$__bs_eh_func" "$__bs_eh_msg" >&2
  fi
  return "$__bs_eh_code"
}

# @description Report an error naming the caller (where the shell can tell) / Сообщить об ошибке с именем вызывающего (там, где оболочка умеет)
# @param $@ message and code, as for errorhandler::throw / сообщение и код, как у errorhandler::throw
bs_error_throw() {
  __bs_eh_who=unknown
  if command -v bs::func_name >/dev/null 2>&1; then
    __bs_eh_who=$(bs::func_name 2)
    # через псевдоним добавляется ещё один кадр / one more frame comes through the alias
    if [ "$__bs_eh_who" = "error::throw" ]; then __bs_eh_who=$(bs::func_name 3); fi
  fi
  bs_errorhandler_throw "$__bs_eh_who" "$@"
}

# ==========================================
# Сигналы / Signals
# ==========================================

# @description Install a handler function for a signal / Установить функцию-обработчик сигнала
# @param $1 signal / сигнал
# @param $2 handler function / функция-обработчик
bs_signal_on() {
  __bs_eh_sig=${1:?signal name required}
  __bs_eh_hnd=${2:?handler function required}
  if ! command -v "$__bs_eh_hnd" >/dev/null 2>&1; then
    bs_log_error "signal::on: handler function not found: ${__bs_eh_hnd}"
    return "${E_ERROR:-1}"
  fi
  # shellcheck disable=SC2064  # имя функции нужно раскрыть сейчас, как и раньше / the function name must expand now, as before
  if ! trap "$__bs_eh_hnd" "$__bs_eh_sig" 2>/dev/null; then
    bs_log_error "signal::on: unknown signal: ${__bs_eh_sig}"
    return "${E_INVALID:-2}"
  fi
}

# @description Ignore a signal / Игнорировать сигнал
# @param $1 signal / сигнал
bs_signal_ignore() {
  __bs_eh_sig=${1:?signal name required}
  trap '' "$__bs_eh_sig" 2>/dev/null || {
    bs_log_error "signal::ignore: unknown signal: ${__bs_eh_sig}"
    return "${E_INVALID:-2}"
  }
}

# @description Reset a signal to its default / Вернуть сигналу поведение по умолчанию
# @param $1 signal / сигнал
bs_signal_reset() {
  __bs_eh_sig=${1:?signal name required}
  trap - "$__bs_eh_sig" 2>/dev/null || {
    bs_log_error "signal::reset: unknown signal: ${__bs_eh_sig}"
    return "${E_INVALID:-2}"
  }
}

# ==========================================
# Выход / Exit
# ==========================================

# @private
# @description Код по имени: E_<ИМЯ>, затем LIB_ERROR_<ИМЯ>; результат в __bs_eh_val, статус 1 — имени нет / A code by name: E_<NAME>, then LIB_ERROR_<NAME>; the result is in __bs_eh_val, status 1 means no such name
# @param $1 name, any case / имя в любом регистре
bs_exit_code() {
  __bs_eh_up=$(bs_str_upper "$1")
  case "$__bs_eh_up" in
    ''|*[!A-Z0-9_]*) return 1 ;;
  esac
  for __bs_eh_prefix in E_ LIB_ERROR_; do
    __bs_eh_val=''
    bs_var_get "${__bs_eh_prefix}${__bs_eh_up}" __bs_eh_val || continue
    if [ -n "$__bs_eh_val" ]; then return 0; fi
  done
  return 1
}

# @description Run the cleanup and exit; the code is a number or a name (E_<NAME> / LIB_ERROR_<NAME>) / Выполнить очистку и выйти; код — число или имя
# @param $1 code or name, default 0 / код или имя, по умолчанию 0
bs_exit() {
  __bs_eh_ecode=${1:-0}
  if ! bs_num_is_uint "$__bs_eh_ecode"; then
    if bs_exit_code "$__bs_eh_ecode"; then
      __bs_eh_ecode=$__bs_eh_val
    else
      bs_log_error "bs::exit: unknown exit code name: ${1:-}"
      __bs_eh_ecode=${E_ERROR:-1}
    fi
  fi
  bs_cleanup_run_all
  exit "$__bs_eh_ecode"
}

# @description Log the message and exit with a code / Записать сообщение в лог и выйти с кодом
# @param $1 message / сообщение
# @param $2 code, default E_ERROR / код, по умолчанию E_ERROR
bs_error_exit() {
  __bs_eh_emsg=${1-}
  __bs_eh_ecd=${2:-${E_ERROR:-1}}
  bs_log_error "$__bs_eh_emsg"
  bs_exit "$__bs_eh_ecd"
}

# @description Log the message and a backtrace (where the shell has one) and exit / Записать сообщение и трассировку (где она есть) и выйти
# @param $1 message / сообщение
# @param $2 code, default E_ERROR / код, по умолчанию E_ERROR
bs_error_exit_with_backtrace() {
  __bs_eh_emsg=${1-}
  __bs_eh_ecd=${2:-${E_ERROR:-1}}
  bs_log_error "$__bs_eh_emsg"
  bs_log_error "Backtrace:"
  if command -v bs::stack_depth >/dev/null 2>&1; then
    __bs_eh_depth=$(bs::stack_depth)
    __bs_eh_frame=1
    while [ "$__bs_eh_frame" -lt $((__bs_eh_depth - 1)) ]; do
      bs_log_error "  $(bs::stack_file $((__bs_eh_frame + 1))):$(bs::stack_line $((__bs_eh_frame + 1))) $(bs::stack_func $((__bs_eh_frame + 1)))(...)"
      __bs_eh_frame=$((__bs_eh_frame + 1))
    done
  else
    bs_log_error "  (no call stack in this shell / в этой оболочке нет стека вызовов)"
  fi
  bs_exit "$__bs_eh_ecd"
}

# ==========================================
# Обработчики по коду / Handlers by code
# ==========================================

# @description Does a function with this name exist? / Существует ли функция с таким именем?
# @param $1 name / имя
bs_function_exists() {
  # статус нормализуем: dash и ash при «не найдено» отдают 127, а не 1 / normalise the status: dash and ash return 127, not 1, for "not found"
  command -v "${1-}" >/dev/null 2>&1 || return 1
}

# @description Handle an error: a registered handler, or log and exit / Обработать ошибку: зарегистрированный обработчик, иначе лог и выход
# @param $1 error code / код ошибки
# @param $2 message / сообщение
bs_error_handle() {
  __bs_eh_hcode=${1-}
  __bs_eh_hmsg=${2-}
  bs_log_error "Error ${__bs_eh_hcode}: ${__bs_eh_hmsg}"
  __bs_eh_handler=$(bs_map_get bs_error_handlers "$__bs_eh_hcode" 2>/dev/null || true)
  if [ -n "$__bs_eh_handler" ]; then
    "$__bs_eh_handler" "$__bs_eh_hmsg"
  else
    bs_error_exit "$__bs_eh_hmsg" "$__bs_eh_hcode"
  fi
}

# @description Register a handler function for an error code / Зарегистрировать функцию-обработчик для кода ошибки
# @param $1 error code / код ошибки
# @param $2 handler function / функция-обработчик
bs_error_set_handler() {
  if [ -z "${1-}" ]; then
    bs_log_warn "error::set_handler: error code is required"
    return "${E_INVALID:-2}"
  fi
  if ! bs_function_exists "${2-}"; then
    bs_log_warn "Handler function does not exist: ${2-}"
    return "${E_ERROR:-1}"
  fi
  bs_map_set bs_error_handlers "$1" "$2"
  bs_log_debug "Set custom handler for error $1: $2"
}

# @description Remove the handler of an error code / Убрать обработчик кода ошибки
# @param $1 error code / код ошибки
bs_error_reset_handler() {
  bs_map_remove bs_error_handlers "${1-}" >/dev/null 2>&1 || true
  bs_log_debug "Reset handler for error ${1-}"
}

# ==========================================
# Выполнение с обработкой / Running with handling
# ==========================================

# @description Run a command; log and return its code on failure / Выполнить команду; при сбое залогировать и вернуть её код
# @param $@ command / команда
bs_error_try() {
  __bs_eh_res=0
  "$@" || __bs_eh_res=$?
  if [ "$__bs_eh_res" -ne 0 ]; then
    bs_log_error "Command failed: $*"
    return "$__bs_eh_res"
  fi
  return 0
}

# @description Run a primary function, and a fallback one if it fails / Выполнить основную функцию, а при сбое — запасную
# @param $1 primary function / основная функция
# @param $2 fallback function / запасная функция
# @param $@ arguments / аргументы
bs_error_try_with_fallback() {
  __bs_eh_prim=${1-}
  __bs_eh_fall=${2-}
  if [ -z "$__bs_eh_prim" ] || [ -z "$__bs_eh_fall" ]; then
    bs_log_warn "error::try_with_fallback: primary and fallback function names are required"
    return "${E_INVALID:-2}"
  fi
  if ! bs_function_exists "$__bs_eh_prim"; then
    bs_log_warn "error::try_with_fallback: primary function not found: ${__bs_eh_prim}"
    return "${E_ERROR:-1}"
  fi
  if ! bs_function_exists "$__bs_eh_fall"; then
    bs_log_warn "error::try_with_fallback: fallback function not found: ${__bs_eh_fall}"
    return "${E_ERROR:-1}"
  fi
  shift 2
  if "$__bs_eh_prim" "$@"; then
    return 0
  fi
  bs_log_warn "Primary function '${__bs_eh_prim}' failed, trying fallback: ${__bs_eh_fall}"
  "$__bs_eh_fall" "$@"
}

# @description Run a command up to N times, a second apart / Выполнить команду до N раз с паузой в секунду
# @param $1 attempts (an integer >= 1) / число попыток (целое >= 1)
# @param $@ command / команда
bs_error_retry() {
  __bs_eh_arg=${1-}
  shift
  # целое >= 1; ведущие нули не делают число восьмеричным (bs_num_dec) / an integer >= 1; leading zeros do not make it octal (bs_num_dec)
  if ! { bs_num_is_uint "$__bs_eh_arg" && __bs_eh_max=$(bs_num_dec "$__bs_eh_arg") && [ "$__bs_eh_max" -ge 1 ]; }; then
    bs_log_error "error::retry: attempts must be an integer >= 1, got: '${__bs_eh_arg}'"
    return "${E_INVALID:-2}"
  fi
  __bs_eh_att=1
  __bs_eh_res=0
  while [ "$__bs_eh_att" -le "$__bs_eh_max" ]; do
    bs_log_debug "Attempt ${__bs_eh_att}/${__bs_eh_max}: $*"
    "$@" && return 0
    __bs_eh_res=$?
    if [ "$__bs_eh_att" -lt "$__bs_eh_max" ]; then
      bs_log_debug "Command failed, retrying in 1 second..."
      sleep 1
    fi
    __bs_eh_att=$((__bs_eh_att + 1))
  done
  bs_log_error "Command failed after ${__bs_eh_max} attempts: $*"
  return "$__bs_eh_res"
}

# @description Run a command and hide its stderr; the status is always 0 / Выполнить команду, скрыв stderr; статус всегда 0
# @param $@ command / команда
bs_error_ignore() {
  "$@" 2>/dev/null || true
}

# @description Run a command with a time limit (without one if timeout is missing) / Выполнить команду с ограничением времени (без него, если нет timeout)
# @param $1 timeout / время
# @param $@ command / команда
bs_error_with_timeout() {
  __bs_eh_to=${1-}
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$__bs_eh_to" "$@"
  else
    bs_log_warn "timeout command not available, running without timeout: $*"
    "$@"
  fi
}

# @description Log a fatal message, run the cleanup and exit at once / Записать фатальное сообщение, выполнить очистку и сразу выйти
# @param $1 message / сообщение
bs_error_panic() {
  bs_log_error "PANIC: ${1-}"
  bs_log_error "System is in an inconsistent state. Terminating immediately."
  bs_cleanup_run_all
  exit "${E_ERROR:-1}"
}

# @description Log an error message / Записать сообщение об ошибке
# @param $1 message / сообщение
bs_error_log() {
  bs_log_error "${1-}"
}

# @description Exit with a message if a predicate function succeeds / Выйти с сообщением, если функция-предикат успешна
# @param $1 predicate function / функция-предикат
# @param $2 message / сообщение
# @param $3 code, default E_ERROR / код, по умолчанию E_ERROR
bs_error_conditional() {
  __bs_eh_pred=${1-}
  __bs_eh_cmsg=${2-}
  __bs_eh_ccode=${3:-${E_ERROR:-1}}
  if [ -z "$__bs_eh_pred" ]; then
    bs_log_warn "error::conditional: predicate function name is required"
    return "${E_INVALID:-2}"
  fi
  if ! bs_function_exists "$__bs_eh_pred"; then
    bs_log_warn "error::conditional: predicate function not found: ${__bs_eh_pred}"
    return "${E_ERROR:-1}"
  fi
  if "$__bs_eh_pred"; then
    bs_error_exit "$__bs_eh_cmsg" "$__bs_eh_ccode"
  fi
}

# @description Warn with a message if a predicate function succeeds / Предупредить, если функция-предикат успешна
# @param $1 predicate function / функция-предикат
# @param $2 message / сообщение
bs_error_conditional_warning() {
  __bs_eh_pred=${1-}
  __bs_eh_cmsg=${2-}
  if [ -z "$__bs_eh_pred" ]; then
    bs_log_warn "error::conditional_warning: predicate function name is required"
    return "${E_INVALID:-2}"
  fi
  if ! bs_function_exists "$__bs_eh_pred"; then
    bs_log_warn "error::conditional_warning: predicate function not found: ${__bs_eh_pred}"
    return "${E_ERROR:-1}"
  fi
  if "$__bs_eh_pred"; then
    bs_log_warn "$__bs_eh_cmsg"
  fi
}

# @description Handler for a missing command: hints a package and exits with 127 / Обработчик отсутствующей команды: подсказывает пакет и выходит с кодом 127
# @param $1 command / команда
bs_error_handler_command_not_found() {
  __bs_eh_cmd=${1-}
  bs_log_error "Command not found: ${__bs_eh_cmd}"
  if command -v apt >/dev/null 2>&1; then
    __bs_eh_pkg=$(apt-cache search "$__bs_eh_cmd" | head -n 1 | awk '{print $1}')
    if [ -n "$__bs_eh_pkg" ]; then
      bs_log_info "You might need to install package: ${__bs_eh_pkg}"
    fi
  elif command -v dnf >/dev/null 2>&1; then
    __bs_eh_pkg=$(dnf search "$__bs_eh_cmd" 2>/dev/null | grep -E '^[[:alnum:]_]' | head -n 1 | awk '{print $1}')
    if [ -n "$__bs_eh_pkg" ]; then
      bs_log_info "You might need to install package: ${__bs_eh_pkg}"
    fi
  fi
  bs_error_exit "Command '${__bs_eh_cmd}' not found" 127
}

bs_shell_alias bs_cleanup_add cleanup::add
bs_shell_alias bs_cleanup_run_all cleanup::__run_all
bs_shell_alias bs_on_exit 'BS::__on_exit'
bs_shell_alias bs_errorhandler_setup_trap errorhandler::setup_trap
bs_shell_alias bs_errorhandler_throw errorhandler::throw
bs_shell_alias bs_error_throw error::throw
bs_shell_alias bs_signal_on signal::on
bs_shell_alias bs_signal_ignore signal::ignore
bs_shell_alias bs_signal_reset signal::reset
bs_shell_alias bs_exit bs::exit
bs_shell_alias bs_error_exit error::exit
bs_shell_alias bs_error_exit_with_backtrace error::exit_with_backtrace
bs_shell_alias bs_function_exists function_exists
bs_shell_alias bs_error_handle error::handle
bs_shell_alias bs_error_set_handler error::set_handler
bs_shell_alias bs_error_reset_handler error::reset_handler
bs_shell_alias bs_error_try error::try
bs_shell_alias bs_error_try_with_fallback error::try_with_fallback
bs_shell_alias bs_error_retry error::retry
bs_shell_alias bs_error_ignore error::ignore
bs_shell_alias bs_error_with_timeout error::with_timeout
bs_shell_alias bs_error_panic error::panic
bs_shell_alias bs_error_log error::log
bs_shell_alias bs_error_conditional error::conditional
bs_shell_alias bs_error_conditional_warning error::conditional_warning
bs_shell_alias bs_error_handler_command_not_found error::handler::command_not_found
