#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, test, eval с проверенными именами, слой данных core/data.sh / valid POSIX sh: case, test, eval with checked names, the data layer core/data.sh
# @tier core — builtins only; works everywhere
# @tier core — только builtin'ы; работает везде
#
# core/args.sh — модуль объявления и валидации параметров скриптов BS
# core/args.sh — script parameter declaration and validation module for BS
#
# Позволяет объявить дерево допустимых параметров один раз, а валидацию,
# сообщения об ошибках и help получить автоматически — из того же дерева.
# Declare the tree of allowed parameters once, and get validation,
# error messages and help automatically — from the same tree.
#
# Использование / Usage:
#   load "core/args"
#
#   # Линейная цепочка: myscript first middle last
#   # Linear chain: myscript first middle last
#   args::define first middle last
#
#   # Ветвление: на уровне 1 можно start ИЛИ stop
#   # Branching: level 1 accepts start OR stop
#   args::level 1 start stop
#
#   args::describe first "First stage of the pipeline"
#
#   args::parse "$@" || exit $?
#   stage="$(args::get 1)"
#
# Поведение args::parse:
#   - неизвестный параметр → ошибка + help, код возврата E_INVALID
#   - параметр есть в дереве, но не на этом уровне → ошибка + help, E_INVALID
#   - параметров больше, чем уровней в дереве → ошибка + help, E_INVALID
#   - -h/--help → help в stdout, код 0, ARGS_HELP_REQUESTED=1
# args::parse behaviour:
#   - unknown parameter → error + help, return code E_INVALID
#   - parameter exists in the tree but at another level → error + help, E_INVALID
#   - more parameters than tree levels → error + help, E_INVALID
#   - -h/--help → help to stdout, code 0, ARGS_HELP_REQUESTED=1
#
# ИМЕНА / NAMES
#   Real functions: bs_args_define, bs_args_level, bs_args_required, bs_args_describe,
#   bs_args_flag, bs_args_flag_describe, bs_args_flag_get, bs_args_flag_is_set, bs_args_has,
#   bs_args_rest, bs_args_help, bs_args_parse, bs_args_reset, bs_args_require, bs_args_get,
#   bs_args_completion; in bash and zsh also args::* (the old names, aliases). args::parse,
#   args::reset and args::require come from lib/compat/args.sh: they also fill the bash arrays
#   ARGS_PARAMS, ARGS_FLAGS and ARGS_REST that scripts read after parsing.
#   Настоящие функции — bs_args_*; в bash и zsh — ещё и args::* (прежние имена, псевдонимы).
#   args::parse, args::reset и args::require приходят из lib/compat/args.sh: они ещё заполняют
#   массивы bash ARGS_PARAMS, ARGS_FLAGS и ARGS_REST, которые скрипты читают после разбора.
#
# ДАННЫЕ / DATA
#   The tree, descriptions, flags and the parse result live in the data layer (core/data.sh):
#   maps bs_args_tree (level → names), bs_args_desc, bs_args_flags (name → bool|value),
#   bs_args_flag_desc, bs_args_flag_def, bs_args_flag_val, bs_args_parsed (the parsed flags);
#   arrays bs_args_params and bs_args_rest.
#   Дерево, описания, флаги и результат разбора живут в слое данных (core/data.sh).
#
# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# shellcheck disable=SC2154,SC2119,SC2120,SC2034  # ARGS_LOADED читают снаружи; переменные присваивает eval (bs_args_mget); bs_args_help и bs_args_max_level без аргументов / variables are assigned by eval (bs_args_mget); bs_args_help and bs_args_max_level take no arguments
bs_guard "ARGS" || return 0

# Зависимости / Dependencies
bs_source_relative "const.sh" "logger.sh" "utils.sh" "data.sh" "lang.sh"

# @global ARGS_VERSION — Module version (category: module-flag)
# @global ARGS_VERSION — Версия модуля (категория: module-flag)
bs_shell_readonly ARGS_VERSION="1.0.0"

# @global ARGS_HELP_REQUESTED — Args: help was requested (0/1) (category: constant)
# @global ARGS_HELP_REQUESTED — Args: запрошена справка (0/1) (категория: constant)
ARGS_HELP_REQUESTED=0

# @global __bs_args_required — Args: internal required-positionals counter (category: private)
# @global __bs_args_required — Args: внутренний счётчик обязательных параметров (категория: private)
__bs_args_required=0

# @global __bs_args_variadic — Args: internal variadic level, 0 = none (category: private)
# @global __bs_args_variadic — Args: внутренний повторяемый уровень, 0 = нет (категория: private)
__bs_args_variadic=0

# ==========================================
# Приватные вспомогательные функции / Private helper functions
# ==========================================

# @private
# @description Значение ключа словаря в переменную; нет ключа — пустая строка
# @description Map value into a variable; a missing key gives an empty string
# @param $1 map  $2 key  $3 variable name (a constant of this file)
bs_args_mget() {
  eval "$3=''"
  bs_map_get_to "$1" "$2" "$3" || :
}

# @private
# @description Наибольший номер уровня в дереве (0, если дерево пусто) / The highest level of the tree (0 if empty)
# @stdout number / число
bs_args_max_level() {
  bs_map_keys_to bs_args_tree bs_args_lk
  eval "$(bs_arr_to_args bs_args_lk)"
  __bs_args_ml=0
  for __bs_args_mk in "$@"; do
    if [ "$__bs_args_mk" -gt "$__bs_args_ml" ]; then __bs_args_ml=$__bs_args_mk; fi
  done
  printf '%s\n' "$__bs_args_ml"
}

# @private
# @description Найти уровень параметра в дереве
# @description Find the level of a parameter in the tree
# @param $1 Parameter name / Имя параметра
# @return Prints level number or empty string / Выводит номер уровня или пустую строку
bs_args_level_of() {
  __bs_args_lo_name=$1
  # Имя с пробелом совпало бы с двумя соседними именами списка / A name with a blank would match two neighbouring names of the list
  case $__bs_args_lo_name in
    *[[:space:]]*) printf '\n'; return "${E_SUCCESS:-0}" ;;
  esac
  bs_map_keys_to bs_args_tree bs_args_lk
  eval "$(bs_arr_to_args bs_args_lk)"
  for __bs_args_lo_k in "$@"; do
    bs_args_mget bs_args_tree "$__bs_args_lo_k" __bs_args_lo_l
    case " $__bs_args_lo_l " in
      *" $__bs_args_lo_name "*)
        printf '%s\n' "$__bs_args_lo_k"
        return "${E_SUCCESS:-0}"
        ;;
    esac
  done
  printf '\n'
}

# @private
# @description Допустим ли параметр на уровне / Is the parameter allowed at the level
# @param $1 level  $2 name
bs_args_is_allowed_at() {
  bs_args_mget bs_args_tree "$1" __bs_args_aa_l
  if [ -z "$__bs_args_aa_l" ]; then return "${E_ERROR:-1}"; fi
  # Имя с пробелом совпало бы с двумя соседними именами списка / A name with a blank would match two neighbouring names of the list
  case $2 in
    *[[:space:]]*) return "${E_ERROR:-1}" ;;
  esac
  case " $__bs_args_aa_l " in
    *" $2 "*) return "${E_SUCCESS:-0}" ;;
  esac
  return "${E_ERROR:-1}"
}

# @private
# @description Проверить значение флага его валидатором (number, enum:a,b или имя функции)
# @description Check a flag value with its validator (number, enum:a,b or a function name)
# @param $1 flag name  $2 value
bs_args_validate_flag_value() {
  __bs_args_vf_flag=${1:-}
  __bs_args_vf_value=${2-}
  bs_args_mget bs_args_flag_val "$__bs_args_vf_flag" __bs_args_vf_v
  if [ -z "$__bs_args_vf_v" ]; then return "${E_SUCCESS:-0}"; fi
  case "$__bs_args_vf_v" in
    number)
      bs_is_number "$__bs_args_vf_value" || return "${E_ERROR:-1}"
      ;;
    enum:*)
      bs_utils_split bs_args_wa "${__bs_args_vf_v#enum:}" ','
      eval "$(bs_arr_to_args bs_args_wa)"
      __bs_args_vf_ok=0
      for __bs_args_vf_i in "$@"; do
        if [ "$__bs_args_vf_i" = "$__bs_args_vf_value" ]; then __bs_args_vf_ok=1; fi
      done
      [ "$__bs_args_vf_ok" -eq 1 ] || return "${E_ERROR:-1}"
      ;;
    *)
      if bs_function_exists "$__bs_args_vf_v"; then
        "$__bs_args_vf_v" "$__bs_args_vf_value" || return "${E_ERROR:-1}"
      else
        return "${E_ERROR:-1}"
      fi
      ;;
  esac
  return "${E_SUCCESS:-0}"
}

# @private
# @description Подсказка по значению флага для сообщения об ошибке / Value hint for an error message
# @param $1 flag name
bs_args_flag_value_hint() {
  bs_args_mget bs_args_flag_val "${1:-}" __bs_args_fh_v
  case "$__bs_args_fh_v" in
    number) printf 'a number\n' ;;
    enum:*) printf 'one of: %s\n' "${__bs_args_fh_v#enum:}" ;;
    *)      printf '%s\n' "$__bs_args_fh_v" ;;
  esac
}

# ==========================================
# Объявление дерева / Tree declaration
# ==========================================

# @description Сбросить объявления и результаты разбора / Reset declarations and parse results
bs_args_reset() {
  bs_map_clear bs_args_tree
  bs_map_clear bs_args_desc
  bs_map_clear bs_args_flags
  bs_map_clear bs_args_flag_desc
  bs_map_clear bs_args_flag_def
  bs_map_clear bs_args_flag_val
  bs_map_clear bs_args_parsed
  bs_arr_clear bs_args_params
  bs_arr_clear bs_args_rest
  __bs_args_required=0
  __bs_args_variadic=0
  ARGS_HELP_REQUESTED=0
}

# @description Объявить линейную цепочку параметров: define a b c = level 1 a, level 2 b, level 3 c
# @description Declare a linear chain of parameters: define a b c = level 1 a, level 2 b, level 3 c
# @param $@ names / имена
bs_args_define() {
  if [ $# -eq 0 ]; then
    bs_log_warn "args::define: at least one parameter name is required"
    return "${E_ERROR:-1}"
  fi
  __bs_args_df_level=1
  for __bs_args_df_name in "$@"; do
    bs_args_level "$__bs_args_df_level" "$__bs_args_df_name" || return "${E_ERROR:-1}"
    __bs_args_df_level=$((__bs_args_df_level + 1))
  done
}

# @description Объявить допустимые параметры уровня; имя с суффиксом ... — повторяемый уровень
# @description Declare the allowed parameters of a level; a name with the ... suffix makes the level variadic
# @param $1 level (positive integer) / номер уровня
# @param $@ names / имена
bs_args_level() {
  __bs_args_lv_level=${1:-}
  if [ $# -gt 0 ]; then shift; fi
  if [ -z "$__bs_args_lv_level" ] || ! bs_is_number "$__bs_args_lv_level" || [ "$__bs_args_lv_level" -eq 0 ]; then
    bs_log_warn "args::level: level must be a positive integer, got: ${__bs_args_lv_level}"
    return "${E_ERROR:-1}"
  fi
  if [ $# -eq 0 ]; then
    bs_log_warn "args::level: at least one parameter name is required"
    return "${E_ERROR:-1}"
  fi
  for __bs_args_lv_name in "$@"; do
    case "$__bs_args_lv_name" in
      *...)
        # Повторяемый уровень / Variadic level
        __bs_args_variadic=$__bs_args_lv_level
        __bs_args_lv_name=${__bs_args_lv_name%...}
        ;;
    esac
    if [ -z "$__bs_args_lv_name" ]; then
      bs_log_warn "args::level: empty parameter name at level ${__bs_args_lv_level}"
      return "${E_ERROR:-1}"
    fi
    if bs_args_is_allowed_at "$__bs_args_lv_level" "$__bs_args_lv_name"; then
      continue  # Уже объявлен / Already declared
    fi
    bs_args_mget bs_args_tree "$__bs_args_lv_level" __bs_args_lv_cur
    if [ -n "$__bs_args_lv_cur" ]; then
      bs_map_set bs_args_tree "$__bs_args_lv_level" "${__bs_args_lv_cur} ${__bs_args_lv_name}"
    else
      bs_map_set bs_args_tree "$__bs_args_lv_level" "$__bs_args_lv_name"
    fi
  done
}

# @description Минимальное число позиционных параметров / Minimum number of positional parameters
# @param $1 count / число
bs_args_required() {
  __bs_args_rq_count=${1:-}
  if [ -z "$__bs_args_rq_count" ] || ! bs_is_number "$__bs_args_rq_count"; then
    bs_log_warn "args::required: count must be a non-negative integer, got: ${__bs_args_rq_count}"
    return "${E_ERROR:-1}"
  fi
  __bs_args_required=$__bs_args_rq_count
  return "${E_SUCCESS:-0}"
}

# @description Описать параметр для help / Describe a parameter for help
# @param $1 name  $2 text
bs_args_describe() {
  # Параметры могут быть не переданы: значения по умолчанию для set -u
  # Parameters may be omitted: defaults for set -u
  __bs_args_ds_name=${1:-}
  if [ -z "$__bs_args_ds_name" ]; then
    bs_log_warn "args::describe: parameter name not specified"
    return "${E_ERROR:-1}"
  fi
  bs_map_set bs_args_desc "$__bs_args_ds_name" "${2:-}"
}

# ==========================================
# Флаги (--key value) / Flags (--key value)
# ==========================================

# @description Объявить флаг: bool (по умолчанию) или value; дефолт и валидатор необязательны
# @description Declare a flag: bool (default) or value; the default and the validator are optional
# @param $1 name (with or without --)  $2 type  $3 default  $4 validator (number, enum:a,b, function)
bs_args_flag() {
  __bs_args_fl_name=${1:-}
  __bs_args_fl_type=${2:-bool}
  # Убираем префикс --, если передан / Strip the -- prefix if given
  __bs_args_fl_name=${__bs_args_fl_name#--}
  if [ -z "$__bs_args_fl_name" ]; then
    bs_log_warn "args::flag: flag name not specified"
    return "${E_ERROR:-1}"
  fi
  if [ "$__bs_args_fl_type" != "bool" ] && [ "$__bs_args_fl_type" != "value" ]; then
    bs_log_warn "args::flag: type must be 'bool' or 'value', got: ${__bs_args_fl_type}"
    return "${E_ERROR:-1}"
  fi
  bs_map_set bs_args_flags "$__bs_args_fl_name" "$__bs_args_fl_type"
  # Пустая строка дефолта означает "дефолта нет" / Empty default = no default
  if [ $# -ge 3 ] && [ -n "${3-}" ]; then
    bs_map_set bs_args_flag_def "$__bs_args_fl_name" "$3"
  fi
  if [ $# -ge 4 ]; then
    bs_map_set bs_args_flag_val "$__bs_args_fl_name" "$4"
  fi
}

# @description Описать флаг для help / Describe a flag for help
# @param $1 name  $2 text
bs_args_flag_describe() {
  __bs_args_fd_name=${1:-}
  __bs_args_fd_name=${__bs_args_fd_name#--}
  if [ -z "$__bs_args_fd_name" ]; then
    bs_log_warn "args::flag_describe: flag name not specified"
    return "${E_ERROR:-1}"
  fi
  bs_map_set bs_args_flag_desc "$__bs_args_fd_name" "${2:-}"
}

# @description Значение флага после разбора или его дефолт; 1, если нет ни того, ни другого
# @description The flag value after parsing, or its default; 1 if neither exists
# @param $1 name
bs_args_flag_get() {
  __bs_args_fg_name=${1:-}
  __bs_args_fg_name=${__bs_args_fg_name#--}
  bs_args_mget bs_args_parsed "$__bs_args_fg_name" __bs_args_fg_v
  if [ -z "$__bs_args_fg_v" ]; then
    # Объявленный дефолт / Declared default
    if bs_map_has bs_args_flag_def "$__bs_args_fg_name"; then
      bs_map_get bs_args_flag_def "$__bs_args_fg_name"
      return "${E_SUCCESS:-0}"
    fi
    return "${E_ERROR:-1}"
  fi
  printf '%s\n' "$__bs_args_fg_v"
}

# @description Передан ли флаг в разборе (даже с пустым значением) / Was the flag given in the parse (even with an empty value)
# @param $1 name
bs_args_flag_is_set() {
  __bs_args_fs_name=${1:-}
  __bs_args_fs_name=${__bs_args_fs_name#--}
  bs_map_has bs_args_parsed "$__bs_args_fs_name"
}

# @description Есть ли непустой позиционный параметр на позиции / Is there a non-empty positional parameter at the position
# @param $1 position (from 1) / позиция
bs_args_has() {
  __bs_args_hs_pos=${1:-}
  if [ -z "$__bs_args_hs_pos" ] || ! bs_is_number "$__bs_args_hs_pos" || [ "$__bs_args_hs_pos" -eq 0 ]; then
    return "${E_ERROR:-1}"
  fi
  __bs_args_hs_v=$(bs_arr_get bs_args_params $((__bs_args_hs_pos - 1))) || return 1
  [ -n "$__bs_args_hs_v" ]
}

# @description Аргументы после "--", по одному в строке / Arguments after "--", one per line
bs_args_rest() {
  if [ "$(bs_arr_len bs_args_rest)" -gt 0 ]; then
    eval "$(bs_arr_to_args bs_args_rest)"
    printf '%s\n' "$@"
  fi
}

# ==========================================
# Help / Справка
# ==========================================

# @description Напечатать справку по объявленному дереву
# @description Print help for the declared tree
#   Help никогда не расходится с валидацией — это тот же источник данных
#   Help never diverges from validation — it is the same data source
# @param $1 [optional] program name / имя программы
# @example
#   args::help "deploy.sh"
bs_args_help() {
  __bs_args_hp_prog=${1:-${0##*/}}

  if [ "$(bs_map_count bs_args_tree)" -eq 0 ] && [ "$(bs_map_count bs_args_flags)" -eq 0 ]; then
    printf 'Usage: %s\n' "$__bs_args_hp_prog"
    printf '(no parameters declared / параметры не объявлены)\n'
    return "${E_SUCCESS:-0}"
  fi

  # Собираем usage-строку по уровням / Build the usage line by levels
  __bs_args_hp_usage="Usage: ${__bs_args_hp_prog}"

  # Флаги в usage-строке / Flags in the usage line
  if [ "$(bs_map_count bs_args_flags)" -gt 0 ]; then
    __bs_args_hp_usage="${__bs_args_hp_usage} [flags]"
  fi

  __bs_args_hp_max=$(bs_args_max_level)

  __bs_args_hp_level=1
  while [ "$__bs_args_hp_level" -le "$__bs_args_hp_max" ]; do
    bs_args_mget bs_args_tree "$__bs_args_hp_level" __bs_args_hp_list
    if [ -n "$__bs_args_hp_list" ]; then
      bs_utils_split bs_args_wa "$__bs_args_hp_list" ' '
      __bs_args_hp_choices=$(bs_arr_join bs_args_wa '|')
      # Повторяемый уровень: суффикс ... / Variadic level: ... suffix
      if [ "$__bs_args_variadic" -eq "$__bs_args_hp_level" ]; then
        __bs_args_hp_choices="${__bs_args_hp_choices}..."
      fi
      __bs_args_hp_usage="${__bs_args_hp_usage} [${__bs_args_hp_choices}]"
    fi
    __bs_args_hp_level=$((__bs_args_hp_level + 1))
  done
  printf '%s\n' "$__bs_args_hp_usage"

  if [ "$(bs_map_count bs_args_tree)" -gt 0 ]; then
    printf '\nParameters / Параметры:\n'

    __bs_args_hp_level=1
    while [ "$__bs_args_hp_level" -le "$__bs_args_hp_max" ]; do
      bs_args_mget bs_args_tree "$__bs_args_hp_level" __bs_args_hp_list
      if [ -n "$__bs_args_hp_list" ]; then
        bs_utils_split bs_args_wa "$__bs_args_hp_list" ' '
        printf '  level %d: %s\n' "$__bs_args_hp_level" "$(bs_arr_join bs_args_wa ' | ')"
        eval "$(bs_arr_to_args bs_args_wa)"
        for __bs_args_hp_item in "$@"; do
          bs_args_mget bs_args_desc "$__bs_args_hp_item" __bs_args_hp_d
          if [ -n "$__bs_args_hp_d" ]; then
            printf '    %-16s — %s\n' "$__bs_args_hp_item" "$__bs_args_hp_d"
          fi
        done
      fi
      __bs_args_hp_level=$((__bs_args_hp_level + 1))
    done
  fi

  # Секция флагов / Flags section
  if [ "$(bs_map_count bs_args_flags)" -gt 0 ]; then
    printf '\nFlags / Флаги:\n'
    # Итерация по отсортированным именам через read / Iterating sorted names via read
    bs_map_keys bs_args_flags | sort | while IFS= read -r __bs_args_hp_flag; do
      bs_args_mget bs_args_flags "$__bs_args_hp_flag" __bs_args_hp_kind
      bs_args_mget bs_args_flag_val "$__bs_args_hp_flag" __bs_args_hp_val
      __bs_args_hp_label="--${__bs_args_hp_flag}"
      if [ "$__bs_args_hp_kind" = "value" ]; then
        # Хинт типа значения: number / enum:a,b / другое
        # Value type hint: number / enum:a,b / other
        __bs_args_hp_hint="value"
        case "$__bs_args_hp_val" in
          number) __bs_args_hp_hint="number" ;;
          enum:*) __bs_args_hp_hint="${__bs_args_hp_val#enum:}" ;;
        esac
        __bs_args_hp_label="--${__bs_args_hp_flag} <${__bs_args_hp_hint}>"
      fi
      bs_args_mget bs_args_flag_desc "$__bs_args_hp_flag" __bs_args_hp_d
      if [ -n "$__bs_args_hp_d" ]; then
        printf '    %-28s — %s' "$__bs_args_hp_label" "$__bs_args_hp_d"
      else
        printf '    %-28s' "$__bs_args_hp_label"
      fi
      # Дефолт в help / Default in help
      if bs_map_has bs_args_flag_def "$__bs_args_hp_flag"; then
        bs_args_mget bs_args_flag_def "$__bs_args_hp_flag" __bs_args_hp_def
        printf ' (default: %s)\n' "$__bs_args_hp_def"
      else
        printf '\n'
      fi
    done
    printf '    %-28s — %s\n' "--help" "Show this help and exit"
  fi
}

# ==========================================
# Валидация / Validation
# ==========================================

# @description Проверить аргументы по объявленному дереву
# @description Validate arguments against the declared tree
#   Успех: заполняет массив bs_args_params, возвращает 0
#   Ошибка: печатает причину и help в stderr, возвращает E_INVALID
#   Success: fills the bs_args_params array, returns 0
#   Error: prints the reason and help to stderr, returns E_INVALID
# @param $@ arguments / аргументы
# @example
#   args::parse "$@" || bs::exit invalid
bs_args_parse() {
  bs_arr_clear bs_args_params
  bs_arr_clear bs_args_rest
  bs_map_clear bs_args_parsed
  ARGS_HELP_REQUESTED=0

  # Запрос help: -h/--help в любой позиции, не только argv[0].
  # Объявленные флаги help/h имеют приоритет — их обработает цикл ниже.
  # Просмотр останавливается на "--" (дальше сырые аргументы) и пропускает
  # значение объявленного флага со значением (--pattern -h).
  # Help request: -h/--help at any position, not only argv[0].
  # Declared flags named help/h take precedence — the loop below handles them.
  # The scan stops at "--" (raw arguments follow) and skips the value of a
  # declared value flag (--pattern -h).
  __bs_args_ps_help=0
  __bs_args_ps_skip=0
  for __bs_args_ps_arg in "$@"; do
    if [ "$__bs_args_ps_arg" = "--" ]; then break; fi
    if [ "$__bs_args_ps_skip" -eq 1 ]; then
      __bs_args_ps_skip=0
      continue
    fi
    case "$__bs_args_ps_arg" in
      --*=*) ;;
      --*)
        bs_args_mget bs_args_flags "${__bs_args_ps_arg#--}" __bs_args_ps_t
        if [ "$__bs_args_ps_t" = "value" ]; then
          __bs_args_ps_skip=1
          continue
        fi
        ;;
    esac
    if [ "$__bs_args_ps_arg" = "-h" ] || [ "$__bs_args_ps_arg" = "--help" ]; then
      __bs_args_ps_key=${__bs_args_ps_arg#--}
      if [ "$__bs_args_ps_arg" = "-h" ]; then __bs_args_ps_key=h; fi
      bs_args_mget bs_args_flags "$__bs_args_ps_key" __bs_args_ps_t
      if [ -z "$__bs_args_ps_t" ]; then __bs_args_ps_help=1; fi
    fi
  done
  if [ "$__bs_args_ps_help" -eq 1 ]; then
    ARGS_HELP_REQUESTED=1
    bs_args_help
    return "${E_SUCCESS:-0}"
  fi

  if [ "$(bs_map_count bs_args_tree)" -eq 0 ] && [ "$(bs_map_count bs_args_flags)" -eq 0 ]; then
    bs_log_error "args::parse: parameter tree is empty, call args::define, args::level or args::flag first"
    return "${E_ERROR:-1}"
  fi

  __bs_args_ps_max=$(bs_args_max_level)
  __bs_args_ps_pos=0

  while [ $# -gt 0 ]; do
    __bs_args_ps_param=$1
    shift

    # Разделитель "--": всё после — сырые аргументы (bs_args_rest)
    # The "--" separator: everything after — raw arguments (bs_args_rest)
    if [ "$__bs_args_ps_param" = "--" ]; then
      if [ $# -gt 0 ]; then bs_arr_push bs_args_rest "$@"; fi
      break
    fi

    # Флаги: --name, --name value, --name=value
    # Flags: --name, --name value, --name=value
    case "$__bs_args_ps_param" in
      --*)
        __bs_args_ps_spec=${__bs_args_ps_param#--}
        __bs_args_ps_name=${__bs_args_ps_spec%%=*}
        __bs_args_ps_inline=""
        __bs_args_ps_has_inline=0
        case "$__bs_args_ps_spec" in
          *=*)
            __bs_args_ps_inline=${__bs_args_ps_spec#*=}
            __bs_args_ps_has_inline=1
            ;;
        esac

        # Неизвестный флаг / Unknown flag
        bs_args_mget bs_args_flags "$__bs_args_ps_name" __bs_args_ps_kind
        if [ -z "$__bs_args_ps_kind" ]; then
          bs_log_error "unknown flag: \"--${__bs_args_ps_name}\""
          bs_args_help >&2
          return "${E_INVALID:-2}"
        fi

        if [ "$__bs_args_ps_kind" = "value" ]; then
          # Флаг со значением: --name=value или --name value
          # Value flag: --name=value or --name value
          if [ "$__bs_args_ps_has_inline" -eq 1 ]; then
            bs_map_set bs_args_parsed "$__bs_args_ps_name" "$__bs_args_ps_inline"
          else
            if [ $# -eq 0 ]; then
              bs_log_error "flag \"--${__bs_args_ps_name}\" requires a value"
              bs_args_help >&2
              return "${E_INVALID:-2}"
            fi
            if [ "$1" = "--" ]; then
              # Разделитель "--" не съедаем: значение отсутствует (пустое);
              # "--" обработает ветка разделителя на следующем шаге
              # Do not eat the "--" separator: the value is missing (empty);
              # the separator branch handles "--" on the next step
              bs_map_set bs_args_parsed "$__bs_args_ps_name" ""
            else
              bs_map_set bs_args_parsed "$__bs_args_ps_name" "$1"
              shift
            fi
          fi
          # Валидация значения / Value validation
          bs_args_mget bs_args_parsed "$__bs_args_ps_name" __bs_args_ps_val
          if ! bs_args_validate_flag_value "$__bs_args_ps_name" "$__bs_args_ps_val"; then
            bs_log_error "flag \"--${__bs_args_ps_name}\" has an invalid value: \"${__bs_args_ps_val}\" (expected $(bs_args_flag_value_hint "$__bs_args_ps_name"))"
            bs_args_help >&2
            return "${E_INVALID:-2}"
          fi
        else
          # bool-флаг не принимает значение / bool flag takes no value
          if [ "$__bs_args_ps_has_inline" -eq 1 ]; then
            bs_log_error "flag \"--${__bs_args_ps_name}\" does not take a value"
            bs_args_help >&2
            return "${E_INVALID:-2}"
          fi
          bs_map_set bs_args_parsed "$__bs_args_ps_name" 1
        fi
        continue
        ;;
    esac

    # Позиционный параметр / Positional parameter
    __bs_args_ps_pos=$((__bs_args_ps_pos + 1))

    # Параметров больше, чем уровней в дереве
    # More parameters than tree levels
    if [ "$__bs_args_ps_pos" -gt "$__bs_args_ps_max" ]; then
      # Повторяемый уровень / Variadic level
      if [ "$__bs_args_variadic" -gt 0 ] && bs_args_is_allowed_at "$__bs_args_variadic" "$__bs_args_ps_param"; then
        bs_arr_push bs_args_params "$__bs_args_ps_param"
        continue
      fi
      bs_log_error "too many parameters: \"${__bs_args_ps_param}\" is beyond level ${__bs_args_ps_max}"
      bs_args_help >&2
      return "${E_INVALID:-2}"
    fi

    # Параметр допустим на этом уровне / Parameter allowed at this level
    if bs_args_is_allowed_at "$__bs_args_ps_pos" "$__bs_args_ps_param"; then
      bs_arr_push bs_args_params "$__bs_args_ps_param"
      continue
    fi

    # Параметр есть в дереве, но на другом уровне
    # Parameter exists in the tree but at another level
    __bs_args_ps_real=$(bs_args_level_of "$__bs_args_ps_param")
    if [ -n "$__bs_args_ps_real" ]; then
      bs_log_error "parameter \"${__bs_args_ps_param}\" belongs to level ${__bs_args_ps_real}, but was used at level ${__bs_args_ps_pos}"
    else
      bs_log_error "unknown parameter: \"${__bs_args_ps_param}\""
    fi
    bs_args_help >&2
    return "${E_INVALID:-2}"
  done

  # Минимальное количество позиционных параметров / Minimum positional count
  if [ "$__bs_args_required" -gt 0 ] && [ "$__bs_args_ps_pos" -lt "$__bs_args_required" ]; then
    bs_log_error "at least ${__bs_args_required} parameter(s) are required, got ${__bs_args_ps_pos}"
    bs_args_help >&2
    return "${E_INVALID:-2}"
  fi

  return "${E_SUCCESS:-0}"
}

# @description Разбор + выход: ошибка → bs_exit invalid, help → bs_exit success
# @description Parse + exit: an error → bs_exit invalid, help → bs_exit success
#   Одна строка вместо идиомы:
#     args::parse "$@" || bs::exit invalid
#     [[ "${ARGS_HELP_REQUESTED}" == "1" ]] && bs::exit success
#   One line instead of the idiom above.
# @param $@ arguments / аргументы
# @example
#   args::require "$@"
bs_args_require() {
  bs_args_parse "$@" || bs_exit invalid
  if [ "${ARGS_HELP_REQUESTED:-0}" = "1" ]; then
    bs_exit success
  fi
  return "${E_SUCCESS:-0}"
}

# @description Позиционный параметр по номеру (с 1); 1, если он пуст и дефолт не задан
# @description A positional parameter by number (from 1); 1 if it is empty and no default is given
#   С дефолтом (третий аргумент): возвращает его вместо ошибки.
#   With a default (second argument): returns it instead of failing.
# @param $1 position  $2 [optional] default
# @stdout the value / значение
# @example
#   stage="$(args::get 1)"
#   env="$(args::get 2 staging)"
bs_args_get() {
  __bs_args_gt_pos=${1:-}

  if [ -z "$__bs_args_gt_pos" ] || ! bs_is_number "$__bs_args_gt_pos" || [ "$__bs_args_gt_pos" -eq 0 ]; then
    bs_log_warn "args::get: position must be a positive integer, got: ${__bs_args_gt_pos}"
    return "${E_ERROR:-1}"
  fi

  __bs_args_gt_v=$(bs_arr_get bs_args_params $((__bs_args_gt_pos - 1))) || __bs_args_gt_v=""
  if [ -z "$__bs_args_gt_v" ]; then
    if [ $# -ge 2 ]; then
      printf '%s\n' "$2"
      return "${E_SUCCESS:-0}"
    fi
    return "${E_ERROR:-1}"
  fi
  printf '%s\n' "$__bs_args_gt_v"
}

# ==========================================
# Автодополнение / Completion
# ==========================================

# @private
# @description Список флагов для генераторов: имя<TAB>вид<TAB>значения, по строке на флаг
# @description Flags for the generators: name<TAB>kind<TAB>values, one flag per line
bs_args_completion_flags() {
  if [ "$(bs_map_count bs_args_flags)" -eq 0 ]; then return 0; fi
  bs_map_keys bs_args_flags | sort | while IFS= read -r __bs_args_cf_n; do
    bs_args_mget bs_args_flags "$__bs_args_cf_n" __bs_args_cf_kind
    bs_args_mget bs_args_flag_val "$__bs_args_cf_n" __bs_args_cf_v
    if [ "$__bs_args_cf_kind" = "value" ]; then
      case "$__bs_args_cf_v" in
        enum:*) printf '%s\tenum\t%s\n' "$__bs_args_cf_n" "${__bs_args_cf_v#enum:}" ;;
        *)      printf '%s\tvalue\t\n' "$__bs_args_cf_n" ;;
      esac
    else
      printf '%s\tbool\t\n' "$__bs_args_cf_n"
    fi
  done
}

# @description Сгенерировать скрипт автодополнения для bash (по умолчанию), zsh, fish или nu
# @description Generate a completion script for bash (default), zsh, fish or nu
#   Вывод можно сохранить в файл и подключить через source или ~/.bashrc
#   The output can be saved to a file and loaded via source or ~/.bashrc
# @param $1 program name / имя программы
# @param $2 [optional] shell: bash (default), zsh, fish, nu; also BS_COMPLETION_SHELL
# @example
#   args::completion "deploy.sh" > /etc/bash_completion.d/deploy.sh
#   args::completion "deploy.sh" zsh > ~/.zfunc/_deploy.sh
# shell-gate: в теле — текст bash-completion (compgen, complete -F), который функция печатает, а не выполняет
# shell-gate: the body holds bash-completion text (compgen, complete -F) that the function prints, not runs
bs_args_completion() {
  __bs_args_cp_prog=${1:-${0##*/}}
  __bs_args_cp_target=$(bs_shell_of_name "${2:-${BS_COMPLETION_SHELL:-bash}}")

  if [ "$(bs_map_count bs_args_tree)" -eq 0 ] && [ "$(bs_map_count bs_args_flags)" -eq 0 ]; then
    bs_log_warn "args::completion: nothing declared, call args::define, args::level or args::flag first"
    return "${E_ERROR:-1}"
  fi

  case "$__bs_args_cp_target" in
    zsh)  bs_args_completion_zsh "$__bs_args_cp_prog"; return $? ;;
    fish) bs_args_completion_fish "$__bs_args_cp_prog"; return $? ;;
    nu)   bs_args_completion_nu "$__bs_args_cp_prog"; return $? ;;
    bash) ;;
    *)
      bs_log_error "args::completion: no generator for '${2:-${BS_COMPLETION_SHELL:-}}' (supported: bash zsh fish nu)"
      return "${E_ERROR:-1}"
      ;;
  esac

  # Имя функции: только [a-zA-Z0-9_] / Function name: [a-zA-Z0-9_] only
  __bs_args_cp_fn="_$(printf '%s' "$__bs_args_cp_prog" | tr -c 'a-zA-Z0-9_' '_')_completion"

  # Список всех флагов для дополнения / All flags for completion
  __bs_args_cp_words="--help"
  __bs_args_cp_vflags=""
  if [ "$(bs_map_count bs_args_flags)" -gt 0 ]; then
    # Список value-флагов (после них значение не дополняется);
    # enum-флаги исключаются — для них дополняются значения
    # Value flags list (their values are not completed);
    # enum flags are excluded — their values ARE completed
    __bs_args_cp_sorted=$(bs_map_keys bs_args_flags | sort)
    bs_arr_from_lines bs_args_cp_names "$__bs_args_cp_sorted"
    eval "$(bs_arr_to_args bs_args_cp_names)"
    for __bs_args_cp_n in "$@"; do
      __bs_args_cp_words="${__bs_args_cp_words} --${__bs_args_cp_n}"
      bs_args_mget bs_args_flags "$__bs_args_cp_n" __bs_args_cp_kind
      bs_args_mget bs_args_flag_val "$__bs_args_cp_n" __bs_args_cp_v
      if [ "$__bs_args_cp_kind" = "value" ]; then
        case "$__bs_args_cp_v" in
          enum:*) ;;
          *) __bs_args_cp_vflags="${__bs_args_cp_vflags} --${__bs_args_cp_n}" ;;
        esac
      fi
    done
  fi

  __bs_args_cp_max=$(bs_args_max_level)

  cat <<EOF
# Bash completion for ${__bs_args_cp_prog} — generated by core/args.sh (args::completion)
# Автодополнение Bash для ${__bs_args_cp_prog} — сгенерировано core/args.sh (args::completion)
${__bs_args_cp_fn}() {
    local cur prev word positional i
    COMPREPLY=()
    cur="\${COMP_WORDS[COMP_CWORD]}"
    prev="\${COMP_WORDS[COMP_CWORD-1]}"
EOF

  # После value-флага значение не дополняем / Do not complete after a value flag
  __bs_args_cp_pat=""
  if [ -n "$__bs_args_cp_vflags" ]; then
    bs_utils_split bs_args_wa "$__bs_args_cp_vflags" ' '
    __bs_args_cp_pat=$(bs_arr_join bs_args_wa '|')
    cat <<EOF

    # value-флаги: значение не дополняется / value flags: value is not completed
    case "\${prev}" in
        ${__bs_args_cp_pat}) return 0 ;;
    esac
EOF
  fi

  # enum-значения для value-флагов / enum values for value flags
  if [ "$(bs_map_count bs_args_flags)" -gt 0 ]; then
    eval "$(bs_arr_to_args bs_args_cp_names)"
    for __bs_args_cp_n in "$@"; do
      bs_args_mget bs_args_flags "$__bs_args_cp_n" __bs_args_cp_kind
      bs_args_mget bs_args_flag_val "$__bs_args_cp_n" __bs_args_cp_v
      if [ "$__bs_args_cp_kind" = "value" ]; then
        case "$__bs_args_cp_v" in
          enum:*)
            __bs_args_cp_enum=$(printf '%s' "${__bs_args_cp_v#enum:}" | tr ',' ' ')
            __bs_args_cp_enum_bar=$(printf '%s' "$__bs_args_cp_enum" | tr ' ' '|')
            cat <<EOF

    # enum-значения: --${__bs_args_cp_n} <${__bs_args_cp_enum_bar}>
    case "\${prev}" in
        --${__bs_args_cp_n}) COMPREPLY=( \$(compgen -W "${__bs_args_cp_enum}" -- "\${cur}") ); return 0 ;;
    esac
EOF
            ;;
        esac
      fi
    done
  fi

  cat <<EOF

    # Дополнение флагов / Flag completion
    if [[ "\${cur}" == --* ]]; then
        COMPREPLY=( \$(compgen -W "${__bs_args_cp_words}" -- "\${cur}") )
        return 0
    fi

    # Считаем уже введённые позиционные параметры (флаги уровней не занимают)
    # Count positionals already entered (flags do not occupy levels)
    positional=0
    for ((i = 1; i < COMP_CWORD; i++)); do
        word="\${COMP_WORDS[i]}"
        case "\${word}" in
EOF

  if [ -n "$__bs_args_cp_vflags" ]; then
    cat <<EOF
            ${__bs_args_cp_pat}) ((++i)) ;;   # пропускаем значение value-флага / skip value flag value
EOF
  fi

  cat <<EOF
            --*) ;;                      # bool-флаг / bool flag
            *) ((++positional)) ;;
        esac
    done

    # Выбираем варианты по уровню / Choices by level
    local choices=""
    case \$((positional + 1)) in
EOF

  __bs_args_cp_level=1
  while [ "$__bs_args_cp_level" -le "$__bs_args_cp_max" ]; do
    bs_args_mget bs_args_tree "$__bs_args_cp_level" __bs_args_cp_list
    if [ -n "$__bs_args_cp_list" ]; then
      printf '        %d) choices="%s" ;;\n' "$__bs_args_cp_level" "$__bs_args_cp_list"
    fi
    __bs_args_cp_level=$((__bs_args_cp_level + 1))
  done

  cat <<EOF
    esac

    COMPREPLY=( \$(compgen -W "\${choices} ${__bs_args_cp_words}" -- "\${cur}") )
    return 0
}
complete -F ${__bs_args_cp_fn} "${__bs_args_cp_prog}"
EOF
}

# ==========================================
# Автодополнение zsh, fish, nushell / Completion for zsh, fish, nushell
# Не проверено на реальных fish и nu: проверяется только текст.
# Not verified on real fish and nu: only the text is tested.
# ==========================================

# @private
bs_args_completion_zsh() {
  __bs_args_zs_prog=$1
  __bs_args_zs_fn="_$(printf '%s' "$__bs_args_zs_prog" | tr -c 'a-zA-Z0-9_' '_')_completion"
  bs_arr_clear bs_args_specs
  bs_arr_push bs_args_specs "'--help[show help]'"
  __bs_args_zs_flags=$(bs_args_completion_flags)
  while IFS="$(printf '\t')" read -r __bs_args_zs_name __bs_args_zs_kind __bs_args_zs_values; do
    [ -n "$__bs_args_zs_name" ] || continue
    case "$__bs_args_zs_kind" in
      enum)
        __bs_args_zs_vals=$(printf '%s' "$__bs_args_zs_values" | tr ',' ' ')
        bs_arr_push bs_args_specs "$(bs_quote "--${__bs_args_zs_name}=:value:(${__bs_args_zs_vals})")" ;;
      value) bs_arr_push bs_args_specs "$(bs_quote "--${__bs_args_zs_name}=:value: ")" ;;
      *)     bs_arr_push bs_args_specs "$(bs_quote "--${__bs_args_zs_name}")" ;;
    esac
  done <<EOF
${__bs_args_zs_flags}
EOF
  __bs_args_zs_max=$(bs_args_max_level)
  __bs_args_zs_level=1
  while [ "$__bs_args_zs_level" -le "$__bs_args_zs_max" ]; do
    bs_args_mget bs_args_tree "$__bs_args_zs_level" __bs_args_zs_list
    if [ -n "$__bs_args_zs_list" ]; then
      bs_arr_push bs_args_specs "$(bs_quote "${__bs_args_zs_level}:argument ${__bs_args_zs_level}:(${__bs_args_zs_list})")"
    fi
    __bs_args_zs_level=$((__bs_args_zs_level + 1))
  done
  printf '#compdef %s\n' "$__bs_args_zs_prog"
  printf '# zsh completion for %s — generated by core/args.sh (args::completion)\n' "$__bs_args_zs_prog"
  printf '# Автодополнение zsh для %s — сгенерировано core/args.sh (args::completion)\n' "$__bs_args_zs_prog"
  printf '%s() {\n  _arguments -S \\\n' "$__bs_args_zs_fn"
  __bs_args_zs_n=$(bs_arr_len bs_args_specs)
  __bs_args_zs_i=0
  while [ "$__bs_args_zs_i" -lt "$__bs_args_zs_n" ]; do
    __bs_args_zs_spec=$(bs_arr_get bs_args_specs "$__bs_args_zs_i")
    if [ "$__bs_args_zs_i" -lt $((__bs_args_zs_n - 1)) ]; then
      printf '    %s \\\n' "$__bs_args_zs_spec"
    else
      printf '    %s\n' "$__bs_args_zs_spec"
    fi
    __bs_args_zs_i=$((__bs_args_zs_i + 1))
  done
  printf '}\n'
  printf 'compdef %s %s\n' "$__bs_args_zs_fn" "$__bs_args_zs_prog"
}

# @private
bs_args_completion_fish() {
  __bs_args_fi_prog=$1
  __bs_args_fi_q=$(bs_quote "$__bs_args_fi_prog")
  printf '# fish completion for %s — generated by core/args.sh (args::completion)\n' "$__bs_args_fi_prog"
  printf '# Автодополнение fish для %s — сгенерировано core/args.sh (args::completion)\n' "$__bs_args_fi_prog"
  printf 'complete -c %s -f\n' "$__bs_args_fi_q"
  printf 'complete -c %s -l help -d %s\n' "$__bs_args_fi_q" "$(bs_quote "show help")"
  __bs_args_fi_flags=$(bs_args_completion_flags)
  while IFS="$(printf '\t')" read -r __bs_args_fi_name __bs_args_fi_kind __bs_args_fi_values; do
    [ -n "$__bs_args_fi_name" ] || continue
    case "$__bs_args_fi_kind" in
      enum)  printf 'complete -c %s -l %s -x -a %s\n' "$__bs_args_fi_q" "$__bs_args_fi_name" "$(bs_quote "$(printf '%s' "$__bs_args_fi_values" | tr ',' ' ')")" ;;
      value) printf 'complete -c %s -l %s -r\n' "$__bs_args_fi_q" "$__bs_args_fi_name" ;;
      *)     printf 'complete -c %s -l %s\n' "$__bs_args_fi_q" "$__bs_args_fi_name" ;;
    esac
  done <<EOF
${__bs_args_fi_flags}
EOF
  __bs_args_fi_max=$(bs_args_max_level)
  __bs_args_fi_level=1
  while [ "$__bs_args_fi_level" -le "$__bs_args_fi_max" ]; do
    bs_args_mget bs_args_tree "$__bs_args_fi_level" __bs_args_fi_list
    if [ -n "$__bs_args_fi_list" ]; then
      printf 'complete -c %s -n %s -a %s\n' "$__bs_args_fi_q" \
        "$(bs_quote "__fish_is_nth_token ${__bs_args_fi_level}")" "$(bs_quote "$__bs_args_fi_list")"
    fi
    __bs_args_fi_level=$((__bs_args_fi_level + 1))
  done
}

# @private
bs_args_completion_nu() {
  __bs_args_nu_prog=$1
  printf '# nushell completion for %s — generated by core/args.sh (args::completion)\n' "$__bs_args_nu_prog"
  printf '# Автодополнение nushell для %s — сгенерировано core/args.sh (args::completion)\n' "$__bs_args_nu_prog"
  bs_arr_clear bs_args_decl
  bs_arr_push bs_args_decl "  --help"
  __bs_args_nu_flags=$(bs_args_completion_flags)
  while IFS="$(printf '\t')" read -r __bs_args_nu_name __bs_args_nu_kind __bs_args_nu_values; do
    [ -n "$__bs_args_nu_name" ] || continue
    case "$__bs_args_nu_kind" in
      enum)
        printf 'def "nu-complete %s --%s" [] { [' "$__bs_args_nu_prog" "$__bs_args_nu_name"
        bs_utils_split bs_args_wa "$__bs_args_nu_values" ','
        eval "$(bs_arr_to_args bs_args_wa)"
        for __bs_args_nu_item in "$@"; do printf ' "%s"' "$__bs_args_nu_item"; done
        printf ' ] }\n'
        bs_arr_push bs_args_decl "  --${__bs_args_nu_name}: string@\"nu-complete ${__bs_args_nu_prog} --${__bs_args_nu_name}\"" ;;
      value) bs_arr_push bs_args_decl "  --${__bs_args_nu_name}: string" ;;
      *)     bs_arr_push bs_args_decl "  --${__bs_args_nu_name}" ;;
    esac
  done <<EOF
${__bs_args_nu_flags}
EOF
  __bs_args_nu_max=$(bs_args_max_level)
  __bs_args_nu_level=1
  while [ "$__bs_args_nu_level" -le "$__bs_args_nu_max" ]; do
    bs_args_mget bs_args_tree "$__bs_args_nu_level" __bs_args_nu_list
    if [ -n "$__bs_args_nu_list" ]; then
      printf 'def "nu-complete %s arg %d" [] { [' "$__bs_args_nu_prog" "$__bs_args_nu_level"
      bs_utils_split bs_args_wa "$__bs_args_nu_list" ' '
      eval "$(bs_arr_to_args bs_args_wa)"
      for __bs_args_nu_item in "$@"; do printf ' "%s"' "$__bs_args_nu_item"; done
      printf ' ] }\n'
      bs_arr_push bs_args_decl "  arg${__bs_args_nu_level}?: string@\"nu-complete ${__bs_args_nu_prog} arg ${__bs_args_nu_level}\""
    fi
    __bs_args_nu_level=$((__bs_args_nu_level + 1))
  done
  printf 'extern "%s" [\n' "$__bs_args_nu_prog"
  eval "$(bs_arr_to_args bs_args_decl)"
  printf '%s\n' "$@"
  printf ']\n'
}

# ==========================================
# Псевдонимы и инициализация / Aliases and initialization
# ==========================================

# args::parse, args::reset и args::require приходят из lib/compat/args.sh (они ещё заполняют
# массивы bash); остальные имена — простые псевдонимы
# args::parse, args::reset and args::require come from lib/compat/args.sh (they also fill the
# bash arrays); the other names are plain aliases
bs_shell_alias bs_args_define args::define
bs_shell_alias bs_args_level args::level
bs_shell_alias bs_args_required args::required
bs_shell_alias bs_args_describe args::describe
bs_shell_alias bs_args_flag args::flag
bs_shell_alias bs_args_flag_describe args::flag_describe
bs_shell_alias bs_args_flag_get args::flag_get
bs_shell_alias bs_args_flag_is_set args::flag_is_set
bs_shell_alias bs_args_has args::has
bs_shell_alias bs_args_rest args::rest
bs_shell_alias bs_args_help args::help
bs_shell_alias bs_args_get args::get
bs_shell_alias bs_args_completion args::completion

ARGS_LOADED="1"

bs_log_debug "Args module initialized, version: ${ARGS_VERSION}" 2>/dev/null || :
