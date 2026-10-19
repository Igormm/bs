#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, printf, command -v; логгер берётся, только если загружен / valid POSIX sh: case, printf, command -v; the logger is used only when loaded
# @tier core — builtins only; works everywhere
#
# core/msg.sh — сообщения модулей: через логгер, если он есть, иначе в stderr
# core/msg.sh — module messages: through the logger when there is one, else to stderr
#
# ЗАЧЕМ / WHY
#   Каждый модуль, который может работать без логгера, писал собственную обёртку «если есть
#   bs_log_error — через неё, иначе printf в stderr»: bs_utils_error (core/utils.sh), bs_calc_log
#   (core/calc.sh), ветки в core/errorhandler.sh, core/data.sh, core/guard.sh. Здесь она одна;
#   модуль звать можно в любой момент загрузки, в том числе раньше логгера.
#   Every module that may run without the logger wrote its own wrapper "through bs_log_error if
#   there is one, else printf to stderr": bs_utils_error (core/utils.sh), bs_calc_log
#   (core/calc.sh), branches in core/errorhandler.sh, core/data.sh, core/guard.sh. Here there is
#   one; the module may be called at any moment of loading, even before the logger.
#
# ФОРМАТ БЕЗ ЛОГГЕРА / FORMAT WITHOUT THE LOGGER
#   «УРОВЕНЬ: текст», слова склеены пробелом независимо от IFS; error и warn — в stderr,
#   info — в stdout. Формат с логгером определяет логгер (BS_LOG_FORMAT, цвет, метка времени).
#   "LEVEL: text", the words joined with a space whatever IFS is; error and warn go to stderr,
#   info to stdout. With the logger its own format applies (BS_LOG_FORMAT, colour, timestamp).
#
# ИМЕНА / NAMES
#   Real functions: bs_msg_error, bs_msg_warn, bs_msg_info, bs_msg_fail, bs_msg_invalid.
#   New API: no old `::` names, so no aliases.
#   Настоящие функции: bs_msg_*. Новый API: прежних имён с `::` нет, псевдонимов нет.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard MSG || return 0

# @private
# @description Слова через пробел независимо от IFS; результат в __bs_msg_text / Words joined with a space whatever IFS is; the result is in __bs_msg_text
# @param $@ words / слова
bs_msg_join() {
  __bs_msg_text=''
  __bs_msg_first=1
  for __bs_msg_w in "$@"; do
    if [ "$__bs_msg_first" = 1 ]; then
      __bs_msg_text=$__bs_msg_w
      __bs_msg_first=0
    else
      __bs_msg_text="$__bs_msg_text $__bs_msg_w"
    fi
  done
}

# @description Сообщить об ошибке: логгер или stderr; статус всегда 0 / Report an error: the logger or stderr; the status is always 0
# @param $@ message words / слова сообщения
bs_msg_error() {
  if command -v bs_log_error >/dev/null 2>&1; then
    bs_log_error "$@"
  else
    bs_msg_join "$@"
    printf 'ERROR: %s\n' "$__bs_msg_text" >&2
  fi
  return 0
}

# @description Предупредить: логгер или stderr; статус всегда 0 / Warn: the logger or stderr; the status is always 0
# @param $@ message words / слова сообщения
bs_msg_warn() {
  if command -v bs_log_warn >/dev/null 2>&1; then
    bs_log_warn "$@"
  else
    bs_msg_join "$@"
    printf 'WARN: %s\n' "$__bs_msg_text" >&2
  fi
  return 0
}

# @description Сообщить: логгер или stdout; статус всегда 0 / Inform: the logger or stdout; the status is always 0
# @param $@ message words / слова сообщения
bs_msg_info() {
  if command -v bs_log_info >/dev/null 2>&1; then
    bs_log_info "$@"
  else
    bs_msg_join "$@"
    printf 'INFO: %s\n' "$__bs_msg_text"
  fi
  return 0
}

# @description Сообщить об ошибке и вернуть E_ERROR (1); функция НЕ завершает скрипт — выход решает вызывающий / Report an error and return E_ERROR (1); the function does NOT end the script — the caller decides about exit
# @param $@ message words / слова сообщения
# @returns E_ERROR (1)
bs_msg_fail() {
  bs_msg_error "$@"
  return "${E_ERROR:-1}"
}

# @description Сообщить о неверном вызове «функция: текст» и вернуть E_INVALID (2) / Report a wrong call "function: text" and return E_INVALID (2)
# @param $1 function name / имя функции
# @param $@ message words / слова сообщения
# @returns E_INVALID (2)
bs_msg_invalid() {
  __bs_msg_fn=${1-unknown}
  shift
  bs_msg_error "${__bs_msg_fn}:" "$@"
  return "${E_INVALID:-2}"
}
