#!/usr/bin/env bash
#
# core/lang.sh — языковые примитивы BS поверх встроенных возможностей Bash
# core/lang.sh — BS language primitives over Bash built-ins
#
# Это «языковое ядро» фреймворка: интроспекция (FUNCNAME, BASH_SOURCE,
# BASH_LINENO), типы (declare -p, [[ -v ]]), строки и коллекции — всё через
# чистый Bash 4+, без внешних команд.
# This is the framework's language kernel: introspection, types, strings and
# collections — pure Bash 4+, no external commands.

# Source Guard
bs::guard "CORE_LANG" || return 0

# Метаданные модуля / Module metadata
# shellcheck disable=SC2034
declare -g CORE_LANG_VERSION="1.0.0"

# ==========================================
# Introspection / Интроспекция
# ==========================================

# @description Name of the calling function (auto-detected).
# @description Имя вызывающей функции (автоопределение).
#   Replaces the `local func_name="my::func"` boilerplate.
# @param $1 [optional] Stack depth (default 1 = immediate caller) / Глубина
# @stdout function name, "main" at script top level
# @example
#   log::debug "entering $(bs::func_name)"
bs::func_name() {
  local -r depth="${1:-1}"
  printf '%s\n' "${FUNCNAME[${depth}]:-main}"
}

# @description Print the current call stack, one frame per line.
# @description Текущий стек вызовов, по фрейму на строку.
# @stdout lines "function (file:line)", caller first
bs::call_stack() {
  local i
  for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
    printf '%s (%s:%s)\n' "${FUNCNAME[i]}" "${BASH_SOURCE[i]}" "${BASH_LINENO[i - 1]}"
  done
}

# @description Predicate: is a function defined? / Определена ли функция?
#   Replaces `declare -F name >/dev/null 2>&1`.
# @return 0 defined, 1 not
bs::is_function() {
  declare -F -- "${1:?function name required}" >/dev/null 2>&1
}

# @description Predicate: is a variable defined? / Определена ли переменная?
#   Replaces `[[ -v name ]]`.
# @return 0 defined, 1 not
bs::is_defined() {
  [[ -v ${1:?variable name required} ]]
}

# @description Detect a variable's (or function's) type.
# @description Определить тип переменной (или функции).
# @param $1 Variable/function name / Имя
# @stdout function | map | array | integer | string | undefined
# @return 0 when defined, 1 when undefined
bs::type_of() {
  local -r name="${1:?variable name required}"

  if bs::is_function "${name}"; then
    printf 'function\n'
    return 0
  fi

  local decl flags
  # declare -p is reliable for scalars, arrays and maps alike; [[ -v name ]]
  # misses maps without a [0] element
  # declare -p надёжен и для скаляров, и для массивов, и для map;
  # [[ -v name ]] промахивается на map без элемента [0]
  if ! decl="$(declare -p "${name}" 2>/dev/null)"; then
    printf 'undefined\n'
    return 1
  fi

  # Flag cluster is the first word after "declare -": "-a", "-Ar", "--", ...
  # Флаговый кластер — первое слово после "declare -": "-a", "-Ar", "--", ...
  flags="${decl#declare -}"
  flags="${flags%% *}"
  case "${flags}" in
    *A*) printf 'map\n' ;;
    *a*) printf 'array\n' ;;
    *i*) printf 'integer\n' ;;
    *) printf 'string\n' ;;
  esac
}

# ==========================================
# Strings / Строки
# ==========================================

# @description Uppercase a string / В верхний регистр. Replaces: ${s^^}
str::upper() {
  printf '%s\n' "${1^^}"
}

# @description Lowercase a string / В нижний регистр. Replaces: ${s,,}
str::lower() {
  printf '%s\n' "${1,,}"
}

# @description Trim leading/trailing whitespace / Обрезать пробелы по краям.
#   Pure Bash (extglob-free parameter expansion), no sed/awk forks.
str::trim() {
  local s="${1-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s\n' "${s}"
}

# @description Replace all occurrences / Заменить все вхождения.
#   Replaces: ${s//old/new}
# @param $1 String, $2 Pattern (glob), $3 Replacement
str::replace() {
  local -r s="${1-}" old="${2-}" new="${3-}"
  printf '%s\n' "${s//${old}/${new}}"
}

# @description Predicate: string contains substring / Строка содержит подстроку.
# @return 0 contains, 1 not
str::contains() {
  [[ "${1-}" == *"${2-}"* ]]
}

# @description Predicate: string starts with prefix / Строка начинается с префикса.
str::starts_with() {
  [[ "${1-}" == "${2-}"* ]]
}

# @description Predicate: string ends with suffix / Строка заканчивается суффиксом.
str::ends_with() {
  [[ "${1-}" == *"${2-}" ]]
}

# ==========================================
# Collections / Коллекции
# ==========================================

# @description Predicate: array contains an exact element.
# @description Массив содержит элемент (точное совпадение).
# @param $1 Array name / Имя массива
# @param $2 Element / Элемент
# @return 0 contains, 1 not
# @example
#   if arr::contains my_tools jq; then ...
arr::contains() {
  local -rn __arr_ref="${1:?array name required}"
  local -r needle="${2-}"
  local item
  for item in "${__arr_ref[@]}"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

# @description Append to an array / Добавить элемент в массив.
# @param $1 Array name, $2 Element / Имя массива, элемент
arr::push() {
  local -rn __arr_ref="${1:?array name required}"
  __arr_ref+=("${2-}")
}

# @description Number of elements in an array / Число элементов массива.
# @stdout element count
arr::length() {
  local -rn __arr_ref="${1:?array name required}"
  printf '%s\n' "${#__arr_ref[@]}"
}

# @description Join array elements with a separator / Склеить массив разделителем.
#   Manual loop: "${arr[*]}" with IFS joins on the FIRST char of IFS only.
#   Ручной цикл: "${arr[*]}" с IFS склеивает только по ПЕРВОМУ символу IFS.
# @param $1 Array name / Имя массива
# @param $2 Separator / Разделитель
# @stdout joined string
# @example
#   arr::join my_tools ", "
arr::join() {
  local -rn __arr_ref="${1:?array name required}"
  local -r sep="${2-}"
  local out="" item
  for item in "${__arr_ref[@]}"; do
    out+="${item}${sep}"
  done
  printf '%s\n' "${out%"${sep}"}"
}

# @description Predicate: map has a key / Ассоциативный массив содержит ключ.
# @param $1 Map name / Имя map
# @param $2 Key / Ключ
# @return 0 has key, 1 not
map::has() {
  local -rn __map_ref="${1:?map name required}"
  [[ -v __map_ref["${2-}"] ]]
}
