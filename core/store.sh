#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2154  # __bs_st_v присваивается через eval, ShellCheck его не видит / __bs_st_v is assigned through eval, which ShellCheck cannot follow
# @shell posix — валидный POSIX sh: значения в переменных __bs_store_v_<имя> и eval с проверенным именем / valid POSIX sh: values in __bs_store_v_<name> variables and eval with a checked name
# @tier core — builtins only; works everywhere
#
# core/store.sh — принудительное хранилище значений: нет прямого $имя, все операции через API
# core/store.sh — an enforced value store: there is no direct $name, every operation goes through the API
#
# ЗАЧЕМ / WHY
#   Слой метаданных (core/var.sh) — контракт и аудит, но прямой доступ `$имя` его обходит.
#   bs_store держит значения в собственных переменных `__bs_store_v_<имя>`, поэтому прямого
#   `$имя` не существует: читать/писать/удалять/экспортировать можно только через bs_store_get/
#   set/unset/export, которые проверяют `@ops` (статус 3) и `@on_invalid` (статус 4). Схему
#   объявляет тот же bs_var_declare, валидацию и события — bs_var_validate/bs_var_notify.
#   The metadata layer (core/var.sh) is a contract and an audit, but a direct `$name` bypasses it.
#   bs_store keeps the values in its own `__bs_store_v_<name>` variables, so no direct `$name`
#   exists: read/write/delete/export only through bs_store_get/set/unset/export, which honour
#   `@ops` (status 3) and `@on_invalid` (status 4). The schema is declared by the same
#   bs_var_declare; validation and events by bs_var_validate/bs_var_notify.
#
# ПРАВИЛА / RULES
#   * Имя — то же, что у bs_var (см. core/var.sh): [A-Za-z_][A-Za-z0-9_]*, не __bs_var_*.
#     A name is the same as bs_var's (see core/var.sh): [A-Za-z_][A-Za-z0-9_]*, not __bs_var_*.
#   * Статус 0 — успех, 1 — нет значения, 2 — плохое имя, 3 — операция запрещена схемой,
#     4 — значение не прошло валидацию.
#     Status 0 is success, 1 is "no such value", 2 is a bad name, 3 is an operation the schema
#     disallows, 4 is a value that failed validation.
#   * bs_store_export создаёт ОБЫЧНУЮ переменную — это явный снимок: после него метаданные и
#     защита теряются (переменная доступна как любой $имя).
#     bs_store_export creates an ORDINARY variable — an explicit snapshot: after it the metadata
#     and the protection are gone (the variable is reachable as any $name).
#   * Опциональный C-бэкенд: задайте BS_STORE_BACKEND (путь бинарника, см.
#     scripts/build_store_helper.sh) и BS_STORE_FILE (файл) — тогда значения живут в файле и
#     переживают процессы; схема/@ops/валидация остаются в shell. Бэкенд хранит значения без
#     перевода строки (протокол — по строке); без него — хранилище в памяти без компилятора.
#     An optional C backend: set BS_STORE_BACKEND (the binary path, see
#     scripts/build_store_helper.sh) and BS_STORE_FILE (the file) — the values then live in the
#     file and survive processes; the schema/@ops/validation stay in the shell. The backend holds
#     values without a newline (the protocol is line-based); without it the store is in-memory,
#     no compiler.

# ИМЕНА / NAMES
#   Real functions: bs_store_has, bs_store_get, bs_store_set, bs_store_unset, bs_store_export,
#   bs_store_list. New API: no old `::` names, so no aliases.
#   Настоящие функции: bs_store_has, bs_store_get, bs_store_set, bs_store_unset, bs_store_export,
#   bs_store_list. Новый API: прежних имён с `::` нет, псевдонимов нет.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard STORE || return 0

# Dependencies / Зависимости
bs_source_relative "var.sh"

# Реестр имён (через пробел); значения — в __bs_store_v_<имя>.
# The registry of names (space-separated); the values live in __bs_store_v_<name>.
__bs_store_reg=

# @description Подключён ли опциональный C-бэкенд (BS_STORE_BACKEND + BS_STORE_FILE заданы, бинарник исполняем) /
#   Whether the optional C backend is wired (BS_STORE_BACKEND + BS_STORE_FILE are set and the binary is executable)
# @returns 0 yes / 1 no
bs_store_has_backend() {
  [ -n "${BS_STORE_BACKEND:-}" ] && [ -n "${BS_STORE_FILE:-}" ] && [ -x "${BS_STORE_BACKEND}" ]
}

# @description Есть ли значение (статус) / Whether a value exists (status)
# @param $1 name / имя
# @returns 0 set / 1 not / 2 bad name
bs_store_has() {
  bs_var_check "${1-}" || return 2
  if bs_store_has_backend; then
    "$BS_STORE_BACKEND" has "$BS_STORE_FILE" "$1" >/dev/null
  else
    eval "[ \"\${__bs_store_v_${1}+x}\" = x ]"
  fi
}

# @description Значение по имени: в stdout или в переменную $2 / The value by name: to stdout or into $2
# @param $1 name / имя
# @param $2 variable for the result, otherwise stdout / переменная для результата, иначе stdout
# @returns 0 ok / 1 no such value / 2 bad name / 3 read not allowed
bs_store_get() {
  bs_var_check "${1-}" || return 2
  bs_var_ops_allowed "$1" read || return 3
  bs_store_has "$1" || return 1
  if bs_store_has_backend; then
    __bs_st_v=$("$BS_STORE_BACKEND" get "$BS_STORE_FILE" "$1") || return $?
  else
    eval "__bs_st_v=\${__bs_store_v_${1}}"
  fi
  if [ -n "${2-}" ]; then
    bs_var_check "$2" || return 2
    eval "${2}=\${__bs_st_v}"
  else
    printf '%s\n' "$__bs_st_v"
  fi
}

# @description Записать значение / Assign a value
# @param $1 name / имя
# @param $2 value (may be empty) / значение (может быть пустым)
# @returns 0 ok / 2 bad name / 3 write not allowed / 4 invalid value
bs_store_set() {
  bs_var_check "${1-}" || return 2
  __bs_st_name=$1
  __bs_st_value=${2-}
  bs_var_ops_allowed "$__bs_st_name" write || return 3
  if bs_var_has_schema "$__bs_st_name"; then
    if ! bs_var_validate "$__bs_st_name" "$__bs_st_value"; then
      __bs_st_pol=$(bs_var_spec_field "$(bs_var_schema "$__bs_st_name")" on_invalid) || __bs_st_pol=
      case "$__bs_st_pol" in
        ignore) ;;
        warn)
          bs_var_notify "$__bs_st_name" set invalid
          ;;
        *)
          bs_var_notify "$__bs_st_name" set invalid
          return 4 ;;
      esac
    fi
  fi
  if bs_store_has_backend; then
    printf '%s\n' "$__bs_st_value" | "$BS_STORE_BACKEND" set "$BS_STORE_FILE" "$__bs_st_name" || return 3
  else
    eval "__bs_store_v_${__bs_st_name}=\${__bs_st_value}"
    case " ${__bs_store_reg:-} " in
      *" $__bs_st_name "*) ;;
      *) __bs_store_reg="${__bs_store_reg}${__bs_store_reg:+ }${__bs_st_name}" ;;
    esac
  fi
  bs_var_notify "$__bs_st_name" set ok
  return 0
}

# @description Удалить значение / Remove a value
# @param $1 name / имя
# @returns 0 ok / 1 no such value / 2 bad name / 3 unset not allowed
bs_store_unset() {
  bs_var_check "${1-}" || return 2
  bs_var_ops_allowed "$1" unset || return 3
  bs_store_has "$1" || return 1
  if bs_store_has_backend; then
    "$BS_STORE_BACKEND" unset "$BS_STORE_FILE" "$1" || return $?
  else
    eval "unset __bs_store_v_${1}"
  fi
  bs_var_notify "$1" unset ok
  return 0
}

# @description Создать обычную переменную-снимок (метаданные и защита теряются) / Create an ordinary snapshot variable (metadata and protection are lost)
# @param $1 name / имя
# @returns 0 ok / 1 no such value / 2 bad name / 3 export not allowed
bs_store_export() {
  bs_var_check "${1-}" || return 2
  bs_var_ops_allowed "$1" export || return 3
  bs_store_has "$1" || return 1
  if bs_store_has_backend; then
    __bs_st_v=$("$BS_STORE_BACKEND" get "$BS_STORE_FILE" "$1") || return $?
  else
    eval "__bs_st_v=\${__bs_store_v_${1}}"
  fi
  eval "${1}=\${__bs_st_v}"
  bs_var_notify "$1" export ok
  return 0
}

# @description Напечатать имена всех значений (по одному в строке) / Print every value's name (one per line)
bs_store_list() {
  if bs_store_has_backend; then
    "$BS_STORE_BACKEND" list "$BS_STORE_FILE"
    return $?
  fi
  __bs_st_r=${__bs_store_reg:-}
  while [ -n "$__bs_st_r" ]; do
    __bs_st_n=${__bs_st_r%% *}
    printf '%s\n' "$__bs_st_n"
    case "$__bs_st_r" in
      *" "*) __bs_st_r=${__bs_st_r#* } ;;
      *) break ;;
    esac
  done
  return 0
}
