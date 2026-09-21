#!/usr/bin/env bash
#
# core/prereq.sh — базовые примитивы ядра BS, доступные априори
# core/prereq.sh — core primitives available a priori to all BS modules
#
# Этот файл не имеет зависимостей и подключается напрямую (raw source).
# It has no dependencies and is sourced directly (raw source).

# Self-guard via raw idiom: bs::guard is defined here, so cannot use it yet.
# Гемор
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

# @description Print the absolute (physical) directory of the caller's file.
#   Replaces the boilerplate: "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)".
#   Note: available only after core/prereq is loaded, so entry-point headers
#   that run before bootstrap/init.sh must keep the raw idiom.
# @param $1 Optional BASH_SOURCE index (default 1 = immediate caller).
# @stdout Absolute directory path (pwd -P).
# @returns 0 on success; 1 if the directory cannot be resolved.
bs::script_dir() {
  local -r idx="${1:-1}"
  (cd -- "$(dirname -- "${BASH_SOURCE[${idx}]}")" >/dev/null 2>&1 && pwd -P)
}

# ==========================================
# Shell detection / Определение оболочки
#
# Рантайм-определение через BASH_VERSION/ZSH_VERSION (а НЕ $SHELL — это
# логин-оболочка, она врёт при source из другой оболочки). Все хелперы —
# чистые builtins, доступны априори, до загрузки ядра.
# Runtime detection via BASH_VERSION/ZSH_VERSION (NOT $SHELL — that is the
# login shell and lies when sourcing from another shell). All helpers are
# pure builtins, available a priori, before the kernel loads.
# ==========================================

# @description Current shell name: bash/zsh/unknown.
# @description Имя текущей оболочки: bash/zsh/unknown.
# @stdout shell name / имя оболочки
bs::shell::name() {
  if [[ -n "${BASH_VERSION:-}" ]]; then
    printf 'bash\n'
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    printf 'zsh\n'
  else
    printf 'unknown\n'
  fi
  return 0
}

# @description Major shell version (bash: BASH_VERSINFO[0], zsh: ZSH_VERSION).
# @description Старшая версия оболочки (bash: BASH_VERSINFO[0], zsh: ZSH_VERSION).
# @stdout major version / старшая версия
bs::shell::version() {
  if [[ -n "${BASH_VERSION:-}" ]]; then
    printf '%s\n' "${BASH_VERSINFO[0]:-0}"
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    printf '%s\n' "${ZSH_VERSION%%.*}"
  else
    printf '0\n'
  fi
  return 0
}

# @description Capability gate: bash 4+ = full kernel (0/1).
# @description Гейт возможностей: bash 4+ = полное ядро (0/1).
# @stdout 1 bash 4+, 0 otherwise / 1 для bash 4+, 0 иначе
bs::shell::ok() {
  if [[ -n "${BASH_VERSION:-}" ]] && (( BASH_VERSINFO[0] >= 4 )); then
    printf '1\n'
  else
    printf '0\n'
  fi
  return 0
}

# @description Sourced vs executed for the DIRECT CALLER: 0 sourced, 1 executed.
# @description Source vs исполнение ПРЯМОГО ВЫЗЫВАЮЩЕГО: 0 при source, 1 при исполнении.
# bash: файл-вызывающий (BASH_SOURCE[1]) равен $0 только если он исполнен
# напрямую; при source $0 — имя оболочки/скрипта-хозяина. zsh: контекст
# исполнения через ZSH_EVAL_CONTEXT ($0 в zsh при source = имя файла).
# In bash the caller file (BASH_SOURCE[1]) equals $0 only when executed
# directly; when sourced, $0 is the host shell/script. zsh uses
# ZSH_EVAL_CONTEXT ($0 becomes the file name when sourced).
# @return 0 caller is sourced / вызывающий подключён через source; 1 executed
bs::shell::is_sourced() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    [[ "${ZSH_EVAL_CONTEXT}" != toplevel* ]]
    return $?
  fi
  [[ "${BASH_SOURCE[1]:-}" != "$0" ]]
  return $?
}
