#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2154  # __bs_var_v и __bs_vm_* присваиваются через eval, ShellCheck их не видит / __bs_var_v and __bs_vm_* are assigned through eval, which ShellCheck cannot follow
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
#   * Статус 0 — успех, 1 — нет такой переменной, 2 — плохое имя или схема,
#     3 — операция запрещена схемой (@ops), 4 — значение не прошло валидацию
#     (или схема изменилась при повторном declare).
#     Status 0 is success, 1 is "no such variable", 2 is a bad name or a bad
#     schema, 3 is an operation the schema disallows (@ops), 4 is a value that
#     failed validation (or a redeclare with a different schema).
#   * Присваивание только-для-чтения переменной завершает нестационарную оболочку (dash, ash,
#     ksh, mksh, zsh, bash — проверено): проверьте bs_var_is_readonly заранее, если не уверены.
#     Assigning to a read-only variable ends a non-interactive shell (dash, ash, ksh, mksh, zsh,
#     bash — verified): call bs_var_is_readonly first when you are not sure.
#
# ИМЕНА / NAMES
#   Real functions: bs_var_is_name, bs_var_is_set, bs_var_is_readonly, bs_var_get, bs_var_set,
#   bs_var_unset, bs_var_default, bs_var_append — the plain accessors; plus the metadata layer
#   bs_var_declare, bs_var_schema, bs_var_validate, bs_var_list, bs_var_describe. No old `::`
#   names, so no aliases.
#   Настоящие функции: bs_var_is_name, bs_var_is_set, bs_var_is_readonly, bs_var_get, bs_var_set,
#   bs_var_unset, bs_var_default, bs_var_append — простые accessors; плюс слой метаданных
#   bs_var_declare, bs_var_schema, bs_var_validate, bs_var_list, bs_var_describe. Прежних имён
#   с `::` нет, псевдонимов нет.
#
# МЕТАДАННЫЕ / METADATA
#   bs_var_declare ИМЯ СПЕЦИФИКАЦИЯ регистрирует схему: сегменты key=value через ";".
#   Ключи: type, ops, scope, visibility, default, range, unit, on_invalid, on_change,
#   secret, since, deprecated, owner, description. Значения не должны содержать ";".
#   Псевдотипы type: string, any, int, uint, bool, name, enum:a|b|c, port.
#   ops: read, write, append, unset, export, snapshot (разделены ","); пусто = всё можно.
#   Схема хранится в переменной __bs_vm_spec_<имя> (eval с проверенным именем), реестр —
#   в __bs_vm_reg. Это контракт и аудит: прямой доступ $имя нельзя перехватить.
#   bs_var_declare NAME SPEC registers a schema: key=value segments joined by ";".
#   Keys: type, ops, scope, visibility, default, range, unit, on_invalid, on_change,
#   secret, since, deprecated, owner, description. Values must not contain ";".
#   Pseudo-types: string, any, int, uint, bool, name, enum:a|b|c, port.
#   ops: read, write, append, unset, export, snapshot (","-separated); empty = all allowed.
#   The schema is stored in __bs_vm_spec_<name> (eval with a checked name), the registry in
#   __bs_vm_reg. It is a contract and an audit, not enforcement: $name cannot be intercepted.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard VAR || return 0

# Реестр объявленных имён (через пробел); схемы — в __bs_vm_spec_<имя>.
# The registry of declared names (space-separated); the schemas live in __bs_vm_spec_<name>.
__bs_vm_reg=

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
  bs_var_ops_allowed "$1" read || return 3
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
  __bs_vm_name=$1
  __bs_vm_value=${2-}
  bs_var_ops_allowed "$__bs_vm_name" write || return 3
  if bs_var_has_schema "$__bs_vm_name"; then
    if ! bs_var_validate "$__bs_vm_name" "$__bs_vm_value"; then
      __bs_vm_pol=$(bs_var_spec_field "$(bs_var_schema "$__bs_vm_name")" on_invalid) || __bs_vm_pol=
      case "$__bs_vm_pol" in
        ignore) ;;
        warn)
          bs_var_notify "$__bs_vm_name" set invalid
          ;;
        *)
          bs_var_notify "$__bs_vm_name" set invalid
          return 4 ;;
      esac
    fi
  fi
  eval "${__bs_vm_name}=\${__bs_vm_value}"
  bs_var_notify "$__bs_vm_name" set ok
  return 0
}

# @description Удалить переменную по имени / Unset a variable by name
# @param $1 name / имя
# @returns 0 ok / 2 bad name
bs_var_unset() {
  bs_var_check "${1-}" || return 2
  bs_var_ops_allowed "$1" unset || return 3
  eval "unset ${1}"
  bs_var_notify "$1" unset ok
  return 0
}

# @description Задать значение, только если переменная не задана или пуста (как : "${X:=v}") / Assign only if the variable is unset or empty (like : "${X:=v}")
# @param $1 name / имя
# @param $2 default value / значение по умолчанию
# @returns 0 ok / 2 bad name
bs_var_default() {
  bs_var_check "${1-}" || return 2
  __bs_vm_name=$1
  bs_var_ops_allowed "$__bs_vm_name" write || return 3
  __bs_vm_value=${2-}
  if bs_var_has_schema "$__bs_vm_name"; then
    if [ -z "$__bs_vm_value" ]; then
      __bs_vm_value=$(bs_var_spec_field "$(bs_var_schema "$__bs_vm_name")" default) || __bs_vm_value=
    fi
  fi
  eval "__bs_vm_cur=\"\${${__bs_vm_name}:-}\""
  [ -n "$__bs_vm_cur" ] && return 0
  if bs_var_has_schema "$__bs_vm_name"; then
    if ! bs_var_validate "$__bs_vm_name" "$__bs_vm_value"; then
      __bs_vm_pol=$(bs_var_spec_field "$(bs_var_schema "$__bs_vm_name")" on_invalid) || __bs_vm_pol=
      case "$__bs_vm_pol" in
        ignore) ;;
        warn) bs_var_notify "$__bs_vm_name" default invalid ;;
        *) bs_var_notify "$__bs_vm_name" default invalid; return 4 ;;
      esac
    fi
  fi
  eval "${__bs_vm_name}=\${__bs_vm_value}"
  bs_var_notify "$__bs_vm_name" default ok
  return 0
}

# @description Дописать строку в конец переменной / Append a string to the end of a variable
# @param $1 name / имя
# @param $2 text to append / добавляемый текст
# @returns 0 ok / 2 bad name
bs_var_append() {
  bs_var_check "${1-}" || return 2
  __bs_vm_name=$1
  __bs_vm_value=${2-}
  if ! bs_var_ops_allowed "$__bs_vm_name" append; then
    bs_var_ops_allowed "$__bs_vm_name" write || return 3
  fi
  if bs_var_has_schema "$__bs_vm_name"; then
    eval "__bs_vm_new=\"\${${__bs_vm_name}-}\${__bs_vm_value}\""
    if ! bs_var_validate "$__bs_vm_name" "$__bs_vm_new"; then
      bs_var_notify "$__bs_vm_name" append invalid
      return 4
    fi
    eval "${__bs_vm_name}=\${__bs_vm_new}"
  else
    eval "${__bs_vm_name}=\"\${${__bs_vm_name}-}\${__bs_vm_value}\""
  fi
  bs_var_notify "$__bs_vm_name" append ok
  return 0
}

# Metadata / Метаданные

# @private
# @description Есть ли схема у переменной (статус) / Whether a variable has a schema (status)
# @param $1 name / имя
# @returns 0 declared / 1 not declared / 2 bad name
bs_var_has_schema() {
  bs_var_check "${1-}" || return 2
  eval "[ \"\${__bs_vm_spec_${1}+x}\" = x ]"
}

# @private
# @description Допустимый ли ключ спецификации / Whether a spec key is allowed
# @param $1 key / ключ
# @returns 0 allowed / 1 not
bs_var_spec_key_ok() {
  case "${1-}" in
    type|ops|scope|visibility|default|range|unit|on_invalid|on_change|secret|since|deprecated|owner|description) return 0 ;;
  esac
  return 1
}

# @private
# @description Валидна ли спецификация: сегменты key=value, ключи известны / Whether a spec is well-formed
# @param $1 spec / спецификация
# @returns 0 ok / 1 not
bs_var_spec_ok() {
  __bs_vm_s=${1-}
  [ -n "$__bs_vm_s" ] || return 0
  while [ -n "$__bs_vm_s" ]; do
    __bs_vm_seg=${__bs_vm_s%%";"*}
    case "$__bs_vm_seg" in
      *=*) __bs_vm_k=${__bs_vm_seg%%=*} ;;
      *) return 1 ;;
    esac
    bs_var_spec_key_ok "$__bs_vm_k" || return 1
    case "$__bs_vm_s" in
      *";"*) __bs_vm_s=${__bs_vm_s#*";"} ;;
      *) break ;;
    esac
  done
  return 0
}

# @private
# @description Значение ключа спецификации (в stdout; нет ключа — статус 1) / A spec key's value (to stdout; a missing key is status 1)
# @param $1 spec / спецификация
# @param $2 key / ключ
bs_var_spec_field() {
  __bs_vm_spec=$1
  __bs_vm_key=$2
  while [ -n "$__bs_vm_spec" ]; do
    __bs_vm_seg=${__bs_vm_spec%%";"*}
    case "$__bs_vm_seg" in
      "$__bs_vm_key"=*) printf '%s' "${__bs_vm_seg#*=}"; return 0 ;;
    esac
    case "$__bs_vm_spec" in
      *";"*) __bs_vm_spec=${__bs_vm_spec#*";"} ;;
      *) break ;;
    esac
  done
  return 1
}

# @private
# @description Разрешена ли операция схемой (пустое ops = всё можно) / Whether the schema allows an operation
# @param $1 name / имя
# @param $2 operation / операция
# @returns 0 allowed / 1 not / 2 bad name
bs_var_ops_allowed() {
  __bs_vm_name=$1
  __bs_vm_op=$2
  bs_var_has_schema "$__bs_vm_name" || return 0
  __bs_vm_ops=$(bs_var_spec_field "$(bs_var_schema "$__bs_vm_name")" ops) || __bs_vm_ops=
  [ -n "$__bs_vm_ops" ] || return 0
  case ",$__bs_vm_ops," in
    *",$__bs_vm_op,"*) return 0 ;;
  esac
  return 1
}

# @private
# @description Целое число (со знаком, без пробелов и +) / An integer (signed, no spaces or +)
# @param $1 value / значение
# @returns 0 ok / 1 not
bs_var_vm_int_ok() {
  case "${1-}" in
    ''|-) return 1 ;;
    -[0-9]*|[0-9]*)
      __bs_vm_d=${1#-}
      case "$__bs_vm_d" in
        ''|*[!0-9]*) return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
  return 0
}

# @private
# @description Беззнаковое целое / An unsigned integer
# @param $1 value / значение
# @returns 0 ok / 1 not
bs_var_vm_uint_ok() {
  case "${1-}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  return 0
}

# @private
# @description Значение входит в enum-список (разделён |) / A value is in an enum list (|-separated)
# @param $1 list / список
# @param $2 value / значение
# @returns 0 ok / 1 not
bs_var_vm_enum_ok() {
  case "|${1}|" in
    *"|${2}|"*) return 0 ;;
  esac
  return 1
}

# @private
# @description Значение в диапазоне min..max (только после проверки числа) / A value is in a min..max range (only after a numeric check)
# @param $1 value / значение
# @param $2 range (min..max) / диапазон
# @returns 0 ok / 1 not
bs_var_vm_range_ok() {
  __bs_vm_v=$1
  __bs_vm_r=$2
  case "$__bs_vm_r" in
    *..*) ;;
    *) return 1 ;;
  esac
  __bs_vm_min=${__bs_vm_r%%..*}
  __bs_vm_max=${__bs_vm_r#*..}
  [ "$__bs_vm_v" -ge "$__bs_vm_min" ] || return 1
  [ "$__bs_vm_v" -le "$__bs_vm_max" ] || return 1
  return 0
}

# @private
# @description Записать событие: аудит (BS_VAR_AUDIT) и hook on_change=hook:имя / Emit an event: audit (BS_VAR_AUDIT) and an on_change=hook:name hook
# @param $1 name / имя
# @param $2 operation / операция
# @param $3 result / результат
bs_var_notify() {
  __bs_vm_name=${1-}
  __bs_vm_op=${2-}
  __bs_vm_res=${3-}
  if [ -n "${BS_VAR_AUDIT:-}" ]; then
    printf 'var=%s op=%s result=%s\n' "$__bs_vm_name" "$__bs_vm_op" "$__bs_vm_res" >&2
  fi
  if bs_var_has_schema "$__bs_vm_name"; then
    __bs_vm_h=$(bs_var_spec_field "$(bs_var_schema "$__bs_vm_name")" on_change) || __bs_vm_h=
    case "$__bs_vm_h" in
      hook:*) __bs_vm_h=${__bs_vm_h#hook:}
              "$__bs_vm_h" "$__bs_vm_name" "$__bs_vm_op" "$__bs_vm_res" ;;
    esac
  fi
  return 0
}

# @description Зарегистрировать схему переменной / Register a variable's schema
# @param $1 name / имя
# @param $2 spec (key=value;...) / спецификация
# @returns 0 ok (idempotent for the same spec) / 2 bad name or spec / 4 redeclare with a different spec
bs_var_declare() {
  bs_var_check "${1-}" || return 2
  __bs_vm_name=$1
  __bs_vm_spec=${2-}
  if ! bs_var_spec_ok "$__bs_vm_spec"; then
    printf 'bs_var_declare: bad spec: %s\n' "$__bs_vm_spec" >&2
    return 2
  fi
  if bs_var_has_schema "$__bs_vm_name"; then
    eval "__bs_vm_old=\${__bs_vm_spec_${__bs_vm_name}}"
    if [ "$__bs_vm_old" = "$__bs_vm_spec" ]; then
      return 0
    fi
    printf 'bs_var_declare: redeclaring %s with a different schema\n' "$__bs_vm_name" >&2
    return 4
  fi
  eval "__bs_vm_spec_${__bs_vm_name}=\${__bs_vm_spec}"
  case " $__bs_vm_reg " in
    *" $__bs_vm_name "*) ;;
    *) __bs_vm_reg="${__bs_vm_reg}${__bs_vm_reg:+ }${__bs_vm_name}" ;;
  esac
  return 0
}

# @description Схема переменной (в stdout) / The variable's schema (to stdout)
# @param $1 name / имя
# @returns 0 ok / 1 not declared / 2 bad name
bs_var_schema() {
  bs_var_check "${1-}" || return 2
  bs_var_has_schema "$1" || return 1
  eval "__bs_vm_spec=\${__bs_vm_spec_${1}}"
  printf '%s\n' "$__bs_vm_spec"
}

# @description Проверить значение по схеме / Validate a value against the schema
# @param $1 name / имя
# @param $2 value / значение
# @returns 0 ok (or no schema) / 4 invalid / 2 bad name
bs_var_validate() {
  bs_var_check "${1-}" || return 2
  __bs_vm_v=${2-}
  bs_var_has_schema "$1" || return 0
  __bs_vm_spec=$(bs_var_schema "$1")
  __bs_vm_t=$(bs_var_spec_field "$__bs_vm_spec" type) || __bs_vm_t=string
  case "$__bs_vm_t" in
    string|any) ;;
    int)  bs_var_vm_int_ok "$__bs_vm_v" || return 4 ;;
    uint) bs_var_vm_uint_ok "$__bs_vm_v" || return 4 ;;
    bool) case "$__bs_vm_v" in 0|1|true|false) ;; *) return 4 ;; esac ;;
    name) bs_var_is_name "$__bs_vm_v" || return 4 ;;
    enum:*) bs_var_vm_enum_ok "${__bs_vm_t#enum:}" "$__bs_vm_v" || return 4 ;;
    port)
      bs_var_vm_uint_ok "$__bs_vm_v" || return 4
      [ "$__bs_vm_v" -ge 1 ] || return 4
      [ "$__bs_vm_v" -le 65535 ] || return 4 ;;
    *) return 4 ;;
  esac
  __bs_vm_r=$(bs_var_spec_field "$__bs_vm_spec" range) || __bs_vm_r=
  if [ -n "$__bs_vm_r" ]; then
    case "$__bs_vm_t" in
      int|uint|port) bs_var_vm_range_ok "$__bs_vm_v" "$__bs_vm_r" || return 4 ;;
    esac
  fi
  return 0
}

# @description Напечатать имена всех объявленных переменных (по одному в строке) / Print every declared variable's name (one per line)
bs_var_list() {
  __bs_vm_r=${__bs_vm_reg:-}
  while [ -n "$__bs_vm_r" ]; do
    __bs_vm_n=${__bs_vm_r%% *}
    printf '%s\n' "$__bs_vm_n"
    case "$__bs_vm_r" in
      *" "*) __bs_vm_r=${__bs_vm_r#* } ;;
      *) break ;;
    esac
  done
  return 0
}

# @description Описать переменную: имя=спецификация (в stdout) / Describe a variable: name=spec (to stdout)
# @param $1 name / имя
# @returns 0 ok / 1 not declared / 2 bad name
bs_var_describe() {
  bs_var_check "${1-}" || return 2
  __bs_vm_s=$(bs_var_schema "$1") || return $?
  printf '%s=%s\n' "$1" "$__bs_vm_s"
  return 0
}
