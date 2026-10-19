#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, eval только с проверенным именем / valid POSIX sh: case, eval only with a checked name
# @tier core — builtins only; works everywhere
#
# core/var.sh — переменные по имени: проверка имени и безопасные get/set без ${!x} и nameref
# core/var.sh — variables by name: a name check and safe get/set without ${!x} and namerefs
#
# ЗАЧЕМ / WHY
#   В POSIX sh нет ${!name} и nameref, а ядру нужны косвенные имена (выходная переменная
#   функции, значение по имени). Проверка имени и eval были скопированы в core/data.sh
#   (bs_data_check, bs_data_ret), core/prereq.sh (bs_guard) и core/errorhandler.sh (bs_exit);
#   здесь они собраны в одном месте. Правила eval — глава 12.10 code-style-guide.
#   POSIX sh has no ${!name} and no namerefs, and the kernel needs indirect names (a function's
#   output variable, a value by name). The name check and the eval were copied in core/data.sh
#   (bs_data_check, bs_data_ret), core/prereq.sh (bs_guard) and core/errorhandler.sh (bs_exit);
#   here they are in one place. The eval rules are chapter 12.10 of the code style guide.
#
# ПРАВИЛА / RULES
#   * Имя — [A-Za-z_][A-Za-z0-9_]*; имена на __bs_var_ (временные этого файла) отвергаются,
#     иначе bs_var_set __bs_var_v x молча ничего бы не сделал.
#     A name is [A-Za-z_][A-Za-z0-9_]*; names starting with __bs_var_ (this file's temporaries)
#     are refused, or bs_var_set __bs_var_v x would silently do nothing.
#   * Статус 0 — успех, 1 — нет такой переменной, 2 — плохое имя.
#     Status 0 is success, 1 is "no such variable", 2 is a bad name.
#   * Присваивание только-для-чтения переменной завершает нестационарную оболочку (dash, ash,
#     ksh, mksh, zsh, bash — проверено): проверьте bs_var_is_readonly заранее, если не уверены.
#     Assigning to a read-only variable ends a non-interactive shell (dash, ash, ksh, mksh, zsh,
#     bash — verified): call bs_var_is_readonly first when you are not sure.
#
# ИМЕНА / NAMES
#   Real functions: bs_var_is_name, bs_var_is_set, bs_var_is_readonly, bs_var_get, bs_var_set,
#   bs_var_unset, bs_var_default, bs_var_append. New API: no old `::` names, so no aliases.
#   Настоящие функции: bs_var_*. Новый API: прежних имён с `::` нет, псевдонимов нет.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard VAR || return 0

# @description Допустимое имя переменной (статус) / Whether a string is a valid variable name (status)
# @param $1 name / имя
# @returns 0 valid / 1 not
bs_var_is_name() {
  case "${1-}" in
    ''|[0-9]*|*[!A-Za-z0-9_]*) return 1 ;;
  esac
  return 0
}

# @private
# @description Проверить имя для eval: допустимое и не наше временное; статус 2 — отказ / Check a name for eval: valid and not our temporary; status 2 is a refusal
# @param $1 name / имя
bs_var_check() {
  if ! bs_var_is_name "${1-}"; then
    printf 'bs_var: invalid variable name: %s\n' "${1-}" >&2
    return 2
  fi
  case "$1" in
    __bs_var_*)
      printf 'bs_var: reserved variable name: %s\n' "$1" >&2
      return 2 ;;
  esac
  return 0
}

# @description Задана ли переменная (пустая, но заданная — да) / Whether a variable is set (set but empty counts)
# @param $1 name / имя
# @returns 0 set / 1 unset / 2 bad name
bs_var_is_set() {
  bs_var_check "${1-}" || return 2
  eval "[ \"\${${1}+x}\" = x ]"
}

# @description Только ли для чтения переменная; проверка в подоболочке, не завершает вызывающего / Whether a variable is read-only; probed in a subshell, so it cannot end the caller
# @param $1 name / имя
# @returns 0 read-only / 1 writable / 2 bad name
bs_var_is_readonly() {
  bs_var_check "${1-}" || return 2
  # присваивание той же величины: сработает ошибка только у readonly / assigning the same value fails only for a read-only variable
  if ( eval "${1}=\${${1}-}" ) 2>/dev/null; then
    return 1
  fi
  return 0
}

# @description Значение переменной по имени: в stdout или в переменную $2 (без подоболочки) / The value of a variable by name: to stdout or into the variable $2 (no subshell)
# @param $1 name / имя
# @param $2 variable for the result, otherwise stdout / переменная для результата, иначе stdout
# @returns 0 ok / 1 unset (nothing is printed or assigned) / 2 bad name
bs_var_get() {
  bs_var_check "${1-}" || return 2
  bs_var_is_set "$1" || return 1
  if [ -n "${2-}" ]; then
    bs_var_check "$2" || return 2
    eval "__bs_var_v=\${${1}}"
    eval "${2}=\${__bs_var_v}"
  else
    eval "__bs_var_v=\${${1}}"
    printf '%s\n' "$__bs_var_v"
  fi
}

# @description Записать значение в переменную по имени / Assign a value to a variable by name
# @param $1 name / имя
# @param $2 value (may be empty, may hold anything) / значение (может быть пустым и любым)
# @returns 0 ok / 2 bad name
bs_var_set() {
  bs_var_check "${1-}" || return 2
  __bs_var_n=$1
  __bs_var_v=${2-}
  eval "${__bs_var_n}=\${__bs_var_v}"
}

# @description Удалить переменную по имени / Unset a variable by name
# @param $1 name / имя
# @returns 0 ok / 2 bad name
bs_var_unset() {
  bs_var_check "${1-}" || return 2
  eval "unset ${1}"
  return 0
}

# @description Задать значение, только если переменная не задана или пуста (как : "${X:=v}") / Assign only if the variable is unset or empty (like : "${X:=v}")
# @param $1 name / имя
# @param $2 default value / значение по умолчанию
# @returns 0 ok / 2 bad name
bs_var_default() {
  bs_var_check "${1-}" || return 2
  __bs_var_n=$1
  __bs_var_v=${2-}
  eval "[ -n \"\${${__bs_var_n}:-}\" ] || ${__bs_var_n}=\${__bs_var_v}"
  return 0
}

# @description Дописать строку в конец переменной / Append a string to the end of a variable
# @param $1 name / имя
# @param $2 text to append / добавляемый текст
# @returns 0 ok / 2 bad name
bs_var_append() {
  bs_var_check "${1-}" || return 2
  __bs_var_n=$1
  __bs_var_v=${2-}
  eval "${__bs_var_n}=\"\${${__bs_var_n}-}\${__bs_var_v}\""
}
