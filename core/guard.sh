#!/usr/bin/env bash
#
# core/guard.sh — единая реализация защиты от повторной загрузки модулей
# core/guard.sh — single implementation of the double-source protection
#
# Заменяет размножённую по модулям идиому / Replaces the duplicated idiom:
#   [[ -n "${__X_SOURCED:-}" ]] && return 0
#   readonly __X_SOURCED=1
#
# Использование в модуле / Usage in a module:
#   source "$(dirname -- "${BASH_SOURCE[0]}")/guard.sh"
#   bs::guard "X" || return 0
#
# где "X" — имя, из которого строится переменная __X_SOURCED
# (регистр не важен: "const" и "CONST" дадут __CONST_SOURCED).
# where "X" is the name used to build the __X_SOURCED variable
# (case-insensitive: "const" and "CONST" both give __CONST_SOURCED).
#
# Модуль, подключающий guard.sh из другого каталога, указывает относительный
# путь до core/, например из lib/io: ../../core/guard.sh
#
# @depends (none)

# Source Guard — guard.sh единственный модуль, который держит идиому вручную
# guard.sh is the only module allowed to keep the raw idiom
[[ -n "${__GUARD_SOURCED:-}" ]] && return 0
readonly __GUARD_SOURCED=1

# @description Проверить и установить метку загрузки модуля / Check-and-set module loaded mark
# @param $1 Имя модуля (без __ и _SOURCED) / Module name (without __ and _SOURCED)
# @returns 0  модуль загружается впервые — метка установлена, продолжайте
# @returns 1  модуль уже был загружен — вызывающий должен сделать return 0
# @example
#   bs::guard "const" || return 0
bs::guard() {
  local -r name="${1:?Module name required}"
  local -r var="__${name^^}_SOURCED"  # const -> __CONST_SOURCED
  # индиректное расширение имени переменной / indirect variable expansion
  [[ -n "${!var:-}" ]] && return 1
  printf -v "${var}" '%s' 1
  readonly "${var}"
  return 0
}

# @description Проверить, загружен ли модуль / Query whether a module is loaded
# @param $1 Имя модуля / Module name
# @returns 0  модуль загружен / loaded
# @returns 1  модуль не загружен / not loaded
# @example
#   bs::guard_loaded "logger" && echo "logger is here"
bs::guard_loaded() {
  local -r name="${1:?Module name required}"
  local -r var="__${name^^}_SOURCED"
  [[ -n "${!var:-}" ]]
}

# @description Source files relative to the caller's location.
# Replaces the verbose idiom:
#   source "$(dirname -- "${BASH_SOURCE[0]}")/some.sh"
# @param $@ Relative file paths from the caller's directory
# @example
#   bs::source_relative "const.sh" "logger.sh"
bs::source_relative() {
  local -r caller_dir="$(dirname -- "${BASH_SOURCE[1]}")"
  local file
  for file in "$@"; do
    # shellcheck disable=SC1090
    source "${caller_dir}/${file}"
  done
}
