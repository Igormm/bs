#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, подстановки параметров, grep/sed; массивы — из core/data.sh / valid POSIX sh: case, parameter expansion, grep/sed; arrays come from core/data.sh
# @tier core — builtins, grep and sed; works everywhere
#
# core/deps.sh — Dependency checker for BS modules
# core/deps.sh — проверка зависимостей для модулей BS
#
# Provides a unified way to check external commands required by modules.
# Modules declare optional dependencies via the @optdeps annotation.
#
# Usage / Использование:
#   load "core/deps"
#   deps::has jq
#   deps::require curl "curl is required for HTTP requests"
#   deps::list_missing "lib/integration/http"
#
# ИМЕНА / NAMES
#   Real functions: bs_deps_has, bs_deps_require, bs_deps_list_missing, bs_deps_check_module,
#   bs_deps_missing_tools (the result goes into a data-layer array) and the private
#   bs_deps_parse_optdeps; in bash and zsh also deps::* (the old names). The old
#   deps::missing_tools, whose result is a REAL bash array, lives in lib/compat/deps.sh.
#   Настоящие функции — bs_deps_*; в bash и zsh — ещё и прежние deps::*. Прежняя
#   deps::missing_tools (результат — НАСТОЯЩИЙ массив bash) — в lib/compat/deps.sh.
#
# @depends core/const, core/logger, core/utils

bs_guard "CORE_DEPS" || return 0

# Зависимости / Dependencies
bs_source_relative "const.sh" "logger.sh" "utils.sh"

# @global CORE_DEPS_VERSION — Module version (category: module-flag)
# @global CORE_DEPS_VERSION — Версия модуля (категория: module-flag)
# shellcheck disable=SC2034  # читают другие модули и тесты / read by other modules and tests
CORE_DEPS_VERSION="1.0.0"

# Private helpers / Приватные вспомогательные функции

# @private
# @description Parse optional dependencies from module header.
# @description Разобрать опциональные зависимости из заголовка модуля.
# @param $1 Module path relative to BS_ROOT / Путь модуля относительно BS_ROOT
# @stdout Space-separated list of commands / Список команд через пробел
bs_deps_parse_optdeps() {
  __bs_dp_file="${BS_ROOT}/${1:-}.sh"
  if [ -z "${1:-}" ] || [ ! -f "$__bs_dp_file" ]; then
    return 0
  fi
  __bs_dp_line=$(grep -m1 "^[[:space:]]*#.*@optdeps" "$__bs_dp_file" 2>/dev/null || true)
  if [ -z "$__bs_dp_line" ]; then
    return 0
  fi
  printf '%s\n' "$__bs_dp_line" | sed 's/.*@optdeps[[:space:]]*//; s/[[:space:]]*$//; s/,[[:space:]]*/ /g; s/[[:space:]]\{1,\}/ /g'
}

# Public API / Публичный API

# @description Check whether a command is available.
# @description Проверить, доступна ли команда.
# @param $1 Command name / Имя команды
# @return 0 if available, 1 otherwise / 0 если доступна, иначе 1
# @example
#   if deps::has jq; then ...; fi
bs_deps_has() {
  if [ -z "${1:-}" ]; then
    bs_log_warn "deps::has: command name required"
    return 1
  fi
  if bs_utils_has "$1"; then
    bs_log_debug "Dependency available: $1"
    return 0
  fi
  bs_log_debug "Dependency missing: $1"
  return 1
}

# @description Require a command; log an error and return a code if it is missing.
# @description Потребовать команду; при отсутствии — ошибка в лог и код возврата.
# @param $1 Command name / Имя команды
# @param $2 Custom error message (optional) / Своё сообщение об ошибке (необязательно)
# @return 0 if available, INTEGRATION_ERROR_MISSING_DEPS otherwise
# @example
#   deps::require curl "HTTP module requires curl"
bs_deps_require() {
  if [ -z "${1:-}" ]; then
    bs_log_warn "deps::require: command name required"
    return "${E_INVALID}"
  fi
  if bs_deps_has "$1"; then
    return 0
  fi
  if [ -n "${2:-}" ]; then
    bs_log_error "$2"
  else
    bs_log_error "Required dependency not found: $1"
  fi
  return "${INTEGRATION_ERROR_MISSING_DEPS}"
}

# @description List the missing optional dependencies of a module (from its @optdeps).
# @description Перечислить недостающие опциональные зависимости модуля (из его @optdeps).
# @param $1 Module path relative to BS_ROOT / Путь модуля относительно BS_ROOT
# @stdout Space-separated missing commands / Недостающие команды через пробел
# @return 0 if nothing is missing, 1 if something is / 0 если всё есть, 1 если чего-то нет
bs_deps_list_missing() {
  if [ -z "${1:-}" ]; then
    bs_log_warn "deps::list_missing: module path required"
    return "${E_INVALID}"
  fi
  __bs_dp_rest=$(bs_deps_parse_optdeps "$1")
  if [ -z "$__bs_dp_rest" ]; then
    return 0
  fi
  __bs_dp_missing=''
  # слова — через подстановки параметров: zsh не делит переменную по IFS / words by parameter expansion: zsh does not split a variable by IFS
  while [ -n "$__bs_dp_rest" ]; do
    __bs_dp_cmd=${__bs_dp_rest%% *}
    case "$__bs_dp_rest" in *' '*) __bs_dp_rest=${__bs_dp_rest#* } ;; *) __bs_dp_rest='' ;; esac
    [ -n "$__bs_dp_cmd" ] || continue
    if ! bs_utils_has "$__bs_dp_cmd"; then
      __bs_dp_missing="${__bs_dp_missing:+${__bs_dp_missing} }${__bs_dp_cmd}"
    fi
  done
  if [ -n "$__bs_dp_missing" ]; then
    printf '%s\n' "$__bs_dp_missing"
    return 1
  fi
  return 0
}

# @description Check a module's optional dependencies; warn if any are missing.
# @description Проверить опциональные зависимости модуля; предупредить, если чего-то нет.
# @param $1 Module path relative to BS_ROOT / Путь модуля относительно BS_ROOT
# @return 0 if satisfied, 1 if something is missing / 0 если всё есть, 1 если чего-то нет
bs_deps_check_module() {
  if [ -z "${1:-}" ]; then
    bs_log_warn "deps::check_module: module path required"
    return "${E_INVALID}"
  fi
  __bs_dp_mod=$1
  __bs_dp_miss=$(bs_deps_list_missing "$__bs_dp_mod" 2>/dev/null || true)
  if [ -n "$__bs_dp_miss" ]; then
    bs_log_warn "Module ${__bs_dp_mod} is missing optional dependencies: ${__bs_dp_miss}"
    return 1
  fi
  bs_log_debug "Module ${__bs_dp_mod} dependencies satisfied"
  return 0
}

# @description Collect missing tools into a data-layer array (package names).
# @description Собрать отсутствующие инструменты в массив слоя данных (имена пакетов).
#   Each spec is "cmd", "cmd:package" or "cmdA|cmdB:package" (alternatives: any one is enough).
#   The package defaults to the command name; several packages can be space-separated.
#   For a REAL bash array use deps::missing_tools from lib/compat/deps.sh.
#   Спецификация — «cmd», «cmd:пакет» или «cmdA|cmdB:пакет» (альтернативы: хватит любой). Пакет
#   по умолчанию — имя команды; пакетов может быть несколько через пробел. Для НАСТОЯЩЕГО
#   массива bash — deps::missing_tools из lib/compat/deps.sh.
# @param $1 Name of the output array (cleared first) / Имя массива-результата (сначала очищается)
# @param $@ Tool specs / Спецификации инструментов
# @return Always 0 — the result is in the array / Всегда 0
# @example
#   bs_deps_missing_tools missing jq xmllint:libxml2-utils "netstat|ss:net-tools iproute2"
bs_deps_missing_tools() {
  __bs_dp_out=${1:?output array name required}
  shift
  bs_arr_clear "$__bs_dp_out" || return 2
  for __bs_dp_spec in "$@"; do
    __bs_dp_cmds=${__bs_dp_spec%%:*}
    __bs_dp_pkg=${__bs_dp_spec#*:}
    __bs_dp_found=1
    # альтернативы cmdA|cmdB / the alternatives cmdA|cmdB
    __bs_dp_alts=$__bs_dp_cmds
    while [ -n "$__bs_dp_alts" ]; do
      # '|' в кавычках: в ksh93 голый | в шаблоне — это альтернатива / '|' is quoted: a bare | in a ksh93 pattern is an alternation
      __bs_dp_alt=${__bs_dp_alts%%'|'*}
      case "$__bs_dp_alts" in *'|'*) __bs_dp_alts=${__bs_dp_alts#*'|'} ;; *) __bs_dp_alts='' ;; esac
      if bs_utils_has "$__bs_dp_alt"; then
        __bs_dp_found=0
        break
      fi
    done
    if [ "$__bs_dp_found" -ne 0 ]; then
      # пакеты через пробел / space-separated packages
      __bs_dp_pk=$__bs_dp_pkg
      while [ -n "$__bs_dp_pk" ]; do
        __bs_dp_p=${__bs_dp_pk%% *}
        case "$__bs_dp_pk" in *' '*) __bs_dp_pk=${__bs_dp_pk#* } ;; *) __bs_dp_pk='' ;; esac
        [ -n "$__bs_dp_p" ] || continue
        bs_arr_push "$__bs_dp_out" "$__bs_dp_p"
      done
    fi
  done
  return 0
}

bs_shell_alias bs_deps_parse_optdeps __deps::parse_optdeps
bs_shell_alias bs_deps_has deps::has
bs_shell_alias bs_deps_require deps::require
bs_shell_alias bs_deps_list_missing deps::list_missing
bs_shell_alias bs_deps_check_module deps::check_module
