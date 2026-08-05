#!/usr/bin/env bash
#
# core/prereq.sh — базовые примитивы ядра BS, доступные априори
# core/prereq.sh — core primitives available a priori to all BS modules
#
# Этот файл не имеет зависимостей и подключается напрямую (raw source).
# It has no dependencies and is sourced directly (raw source).

# Self-guard via raw idiom: bs::guard is defined here, so cannot use it yet.
[[ -n "${__PREREQ_SOURCED:-}" ]] && return 0
readonly __PREREQ_SOURCED=1

# @description Check-and-set module loaded mark.
# @param $1 Module name (without __ and _SOURCED).
# @returns 0 first load; 1 already loaded — caller should return 0.
bs::guard() {
  local -r name="${1:?Module name required}"
  local -r var="__${name^^}_SOURCED"
  [[ -n "${!var:-}" ]] && return 1
  printf -v "${var}" '%s' 1
  readonly "${var}"
  return 0
}

# @description Query whether a module is loaded.
# @param $1 Module name.
# @returns 0 loaded; 1 not loaded.
bs::guard_loaded() {
  local -r name="${1:?Module name required}"
  local -r var="__${name^^}_SOURCED"
  [[ -n "${!var:-}" ]]
}

# @description Source files relative to the caller's directory.
# @param $@ Relative file paths from the caller's directory.
bs::source_relative() {
  local -r caller_dir="$(dirname -- "${BASH_SOURCE[1]}")"
  local file
  for file in "$@"; do
    # shellcheck disable=SC1090
    source "${caller_dir}/${file}"
  done
}
