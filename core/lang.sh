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

# @description Pad a string on the right to a width (Python: s.ljust(n)).
# @description Дополнить строку справа до ширины (Python: s.ljust(n)).
# @param $1 String / Строка
# @param $2 Target width, non-negative integer / Целевая ширина, целое число >= 0
# @param $3 [optional] Pad character, default space / Символ заполнения, по умолчанию пробел
# @return 0 ok, 1 invalid width or multi-char pad
# @example
#   name="$(str::pad "$name" 12 ".")"
str::pad() {
  local -r __str_s="${1:?string required}"
  local -r __str_n="${2:?width required}"
  local -r __str_char="${3- }"
  [[ "${__str_n}" =~ ^[0-9]+$ ]] || return 1
  [[ "${#__str_char}" -le 1 ]] || return 1

  local -ri __str_len="${#__str_s}"
  if (( __str_len >= __str_n )); then
    printf '%s\n' "${__str_s}"
    return 0
  fi

  local -i __str_need=$(( __str_n - __str_len ))
  local __str_pad=""
  printf -v __str_pad "%${__str_need}s" ""
  if [[ "${__str_char}" != " " ]]; then
    __str_pad="${__str_pad// /${__str_char}}"
  fi
  printf '%s\n' "${__str_s}${__str_pad}"
}

# @description Repeat a string N times (Python: s * n).
# @description Повторить строку N раз (Python: s * n).
# @param $1 String / Строка
# @param $2 Count, non-negative integer / Количество, целое число >= 0
# @return 0 ok, 1 invalid count
# @example
#   line="$(str::repeat "-" 40)"
str::repeat() {
  local -r __str_s="${1:?string required}"
  local -r __str_n="${2:?count required}"
  [[ "${__str_n}" =~ ^[0-9]+$ ]] || return 1

  local -i __str_i
  local __str_out=""
  for (( __str_i = 0; __str_i < __str_n; __str_i++ )); do
    __str_out+="${__str_s}"
  done
  printf '%s\n' "${__str_out}"
}

# @description Split a string into lines (Python: s.splitlines()).
# @description Разбить строку на строки (Python: s.splitlines()).
#   Empty lines inside the string are kept; a single trailing newline is dropped.
#   Пустые строки внутри сохраняются; один завершающий перевод строки отбрасывается.
# @param $1 String / Строка
# @param $2 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @example
#   str::lines "$(cat /etc/hosts)" hosts
str::lines() {
  local -rn __str_out="${2:?output array name required}"
  (( $# >= 1 )) || return 1
  local __str_s="${1-}"
  __str_s="${__str_s%$'\n'}"
  __str_out=()
  is::empty "${__str_s}" && return 0
  local __str_line
  while IFS= read -r __str_line; do
    __str_out+=("${__str_line}")
  done <<< "${__str_s}"
}

# @description Split a string into whitespace-separated words (Python: s.split()).
# @description Разбить строку на слова по пробелам (Python: s.split()).
# @param $1 String / Строка
# @param $2 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @example
#   str::words "a b  c" w     # w = (a b c)
str::words() {
  local -rn __str_out="${2:?output array name required}"
  (( $# >= 1 )) || return 1
  local -r __str_s="${1-}"
  __str_out=()
  if is::not_empty "${__str_s}"; then
    local -a __str_tmp=()
    read -ra __str_tmp <<< "${__str_s}"
    __str_out=("${__str_tmp[@]}")
  fi
}

# @description Format a string with named and positional placeholders
# @description Отформатировать строку с именованными и позиционными
#   плейсхолдерами (C++23 std::print / Python f-strings).
#   Named: `{name}` from `key=value` args; positional: `{1}`, `{2}`.
# @param $1 Format string / Строка формата
# @param $@ `key=value` pairs or positional values / пары или позиционные
# @stdout the formatted string / отформатированная строка
# @return 0 ok, 1 empty format
# @example
#   str::format "hello {name}, attempt {1}" name=world 42
#   # hello world, attempt 42
str::format() {
  local -r __st_fmt="${1:?format required}"
  shift
  local __st_result="${__st_fmt}"
  local __st_pair __st_key __st_val
  local -i __st_i=1
  for __st_pair in "$@"; do
    if [[ "${__st_pair}" == *=* ]]; then
      __st_key="${__st_pair%%=*}"
      __st_val="${__st_pair#*=}"
      __st_result="${__st_result//\{${__st_key}\}/${__st_val}}"
    else
      __st_result="${__st_result//\{${__st_i}\}/${__st_pair}}"
      __st_i=$(( __st_i + 1 ))
    fi
  done
  printf '%s\n' "${__st_result}"
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
  local __joined="" item
  for item in "${__arr_ref[@]}"; do
    __joined+="${item}${sep}"
  done
  printf '%s\n' "${__joined%"${sep}"}"
}

# @description Read lines from stdin into an array (mapfile).
# @description Прочитать строки со stdin в массив (mapfile).
#   Linguistic replacement for `mapfile -t arr < file` and the dangerous
#   `for i in $(cmd)` loop. NOTE: `cmd | arr::from_lines arr` runs in a
#   subshell — the array will NOT survive; use process substitution.
#   ВНИМАНИЕ: `cmd | arr::from_lines arr` выполняется в subshell — массив
#   НЕ сохранится; используйте подстановку процесса.
# @param $1 Array name / Имя массива
# @stdin lines to read / строки для чтения
# @example
#   arr::from_lines my_files < listing.txt
#   arr::from_lines my_pids < <(pgrep bash)
arr::from_lines() {
  local -rn __arr_ref="${1:?array name required}"
  mapfile -t __arr_ref
}

# @description Predicate: map has a key / Ассоциативный массив содержит ключ.
# @param $1 Map name / Имя map
# @param $2 Key / Ключ
# @return 0 has key, 1 not
map::has() {
  local -rn __map_ref="${1:?map name required}"
  [[ -v __map_ref["${2-}"] ]]
}

# @description Value by key with optional default (Python: m.get(k, default)).
# @description Значение по ключу с опциональным дефолтом (Python: m.get(k, default)).
#   With a default: prints it and returns 0 on a missing key. Without a
#   default: prints nothing and returns 1.
# @param $1 Map name / Имя map
# @param $2 Key / Ключ
# @param $3 [optional] Default value / Значение по умолчанию
# @stdout value (or default) / значение (или дефолт)
# @return 0 key present (or default given), 1 key missing without default
# @example
#   port="$(map::get cfg port 8080)"
map::get() {
  local -rn __map_ref="${1:?map name required}"
  local -r __map_key="${2:?key required}"
  local -r __map_default="${3-}"
  if [[ -v __map_ref["${__map_key}"] ]]; then
    printf '%s\n' "${__map_ref["${__map_key}"]}"
    return 0
  fi
  if (( $# >= 3 )); then
    printf '%s\n' "${__map_default}"
    return 0
  fi
  return 1
}

# @description Set a key/value (map must be declared -A).
# @description Установить ключ/значение (map должен быть объявлен -A).
# @param $1 Map name / Имя map
# @param $2 Key / Ключ
# @param $3 Value / Значение
# @example
#   map::set cfg debug 1
map::set() {
  local -rn __map_ref="${1:?map name required}"
  __map_ref["${2:?key required}"]="${3:?value required}"
}

# @description Remove keys from a map (Python: del m[k]).
# @description Удалить ключи из map (Python: del m[k]).
#   Rebuilds the map instead of `unset 'm[k]'` — unset on associative array
#   elements is broken in Bash 5.3 (wipes the whole map).
#   Пересобирает map вместо `unset 'm[k]'` — unset элементов ассоциативного
#   массива сломан в Bash 5.3 (стирает весь map).
# @param $1 Map name / Имя map
# @param $@ Keys to remove / Ключи для удаления
# @example
#   map::remove cfg debug verbose
map::remove() {
  local -rn __map_ref="${1:?map name required}"
  shift
  local -A __map_rm=()
  local __map_key
  for __map_key in "$@"; do
    __map_rm["${__map_key}"]=1
  done
  local -A __map_tmp=()
  for __map_key in "${!__map_ref[@]}"; do
    [[ -v __map_rm["${__map_key}"] ]] || __map_tmp["${__map_key}"]="${__map_ref["${__map_key}"]}"
  done
  __map_ref=()
  for __map_key in "${!__map_tmp[@]}"; do
    __map_ref["${__map_key}"]="${__map_tmp["${__map_key}"]}"
  done
}

# @description Merge maps into a destination (Python: dst.update(src)).
# @description Склеить map в назначение (Python: dst.update(src)).
#   Later maps overwrite earlier keys. Destination may be created here.
#   Поздние map перезаписывают ключи. Назначение может быть создано здесь.
# @param $1 Destination map name (may be created) / Имя map-назначения (может быть создан)
# @param $@ Source map names / Имена исходных map
# @return 0 ok, 1 destination cannot be an associative array
# @example
#   map::merge all_defaults overrides user_cfg
map::merge() {
  local -r __map_dst_name="${1:?destination map name required}"
  shift
  declare -g -A "${__map_dst_name}" 2>/dev/null || return 1
  local -rn __map_dst="${__map_dst_name}"
  local __map_src_name __map_key
  for __map_src_name in "$@"; do
    local -n __map_src="${__map_src_name}"
    for __map_key in "${!__map_src[@]}"; do
      __map_dst["${__map_key}"]="${__map_src["${__map_key}"]}"
    done
  done
}

# @description Invert a map: values become keys (Python: {v: k for k, v in m.items()}).
# @description Инвертировать map: значения становятся ключами
#   (Python: {v: k for k, v in m.items()}). Duplicate values: last key wins.
#   Повторяющиеся значения: побеждает последний ключ.
# @param $1 Source map name / Имя исходного map
# @param $2 Output map name (may be created) / Имя выходного map (может быть создан)
# @return 0 ok, 1 output cannot be an associative array
# @example
#   map::invert users by_id
map::invert() {
  local -rn __map_src="${1:?source map name required}"
  local -r __map_out_name="${2:?output map name required}"
  declare -g -A "${__map_out_name}" 2>/dev/null || return 1
  local -rn __map_out="${__map_out_name}"
  local __map_key
  __map_out=()
  for __map_key in "${!__map_src[@]}"; do
    __map_out["${__map_src["${__map_key}"]}"]="${__map_key}"
  done
}

# @description Sum of numeric elements (Python: sum(a)).
# @description Сумма числовых элементов (Python: sum(a)).
# @param $1 Array name / Имя массива
# @stdout sum / сумма
# @return 0 ok, 1 non-numeric element
arr::sum() {
  local -rn __arr_ref="${1:?array name required}"
  local -i __arr_sum=0
  local __arr_elem
  for __arr_elem in "${__arr_ref[@]}"; do
    [[ "${__arr_elem}" =~ ^-?[0-9]+$ ]] || return 1
    __arr_sum=$(( __arr_sum + __arr_elem ))
  done
  printf '%s\n' "${__arr_sum}"
}

# @description Minimum of numeric elements (Python: min(a)).
# @description Минимум числовых элементов (Python: min(a)).
# @param $1 Array name / Имя массива
# @stdout min / минимум
# @return 0 ok, 1 empty array or non-numeric element
arr::min() {
  local -rn __arr_ref="${1:?array name required}"
  local __arr_min="" __arr_elem
  for __arr_elem in "${__arr_ref[@]}"; do
    [[ "${__arr_elem}" =~ ^-?[0-9]+$ ]] || return 1
    if is::empty "${__arr_min}" || (( __arr_elem < __arr_min )); then
      __arr_min="${__arr_elem}"
    fi
  done
  is::empty "${__arr_min}" && return 1
  printf '%s\n' "${__arr_min}"
}

# @description Maximum of numeric elements (Python: max(a)).
# @description Максимум числовых элементов (Python: max(a)).
# @param $1 Array name / Имя массива
# @stdout max / максимум
# @return 0 ok, 1 empty array or non-numeric element
arr::max() {
  local -rn __arr_ref="${1:?array name required}"
  local __arr_max="" __arr_elem
  for __arr_elem in "${__arr_ref[@]}"; do
    [[ "${__arr_elem}" =~ ^-?[0-9]+$ ]] || return 1
    if is::empty "${__arr_max}" || (( __arr_elem > __arr_max )); then
      __arr_max="${__arr_elem}"
    fi
  done
  is::empty "${__arr_max}" && return 1
  printf '%s\n' "${__arr_max}"
}

# @description Unique elements, first occurrence order kept (Python: list(dict.fromkeys(a))).
# @description Уникальные элементы с сохранением порядка первого вхождения
#   (Python: list(dict.fromkeys(a))).
# @param $1 Source array name / Имя исходного массива
# @param $2 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @example
#   arr::uniq events unique_events
arr::uniq() {
  local -rn __arr_src="${1:?source array name required}"
  local -rn __arr_out="${2:?output array name required}"
  local -A __arr_seen=()
  local __arr_elem
  __arr_out=()
  for __arr_elem in "${__arr_src[@]}"; do
    [[ -v __arr_seen["${__arr_elem}"] ]] && continue
    __arr_seen["${__arr_elem}"]=1
    __arr_out+=("${__arr_elem}")
  done
}

# ==========================================
# Slicing / Слайсы
#
# Python-style slicing for humans: empty START/END mean "from the beginning"
# / "to the end", negative indices count from the end, END is exclusive,
# STEP may be negative to reverse. Fast paths use native Bash slicing
# (zero forks), slow paths are pure index loops.
# Питоно-подобные слайсы для людей: пустые START/END означают «с начала»
# / «до конца», отрицательные индексы считаются с конца, END не включается,
# отрицательный STEP разворачивает последовательность. Быстрые пути —
# на нативных слайсах Bash (ноль форков), медленные — на индексных циклах.
#
# Naming hazard: Bash resolves namerefs DYNAMICALLY, so a local variable
# in a slice function shadows a caller's array of the same name. All slice
# locals use the reserved prefixes __sl_/__arr_/__map_/__b_ — never name
# your arrays/maps/variables with these prefixes.
# Опасность имён: Bash резолвит nameref ДИНАМИЧЕСКИ, поэтому локальная
# переменная slice-функции затеняет массив вызывающего с тем же именем.
# Все локальные переменные слайсов используют зарезервированные префиксы
# __sl_/__arr_/__map_/__b_ — не называйте свои переменные этими префиксами.
# ==========================================

# @description Normalize slice bounds to [0, len] / [-1, len-1] ranges.
# @description Нормализовать границы слайса к диапазонам [0, len] / [-1, len-1].
#   Shared by arr::slice and str::slice. Private, do not call directly.
# @param $1 Output var name for normalized START / Имя выходной переменной START
# @param $2 Output var name for normalized END / Имя выходной переменной END
# @param $3 Output var name for normalized STEP / Имя выходной переменной STEP
# @param $4 Length of the collection / Длина коллекции
# @param $5 Raw START (empty = default) / Сырой START (пусто = по умолчанию)
# @param $6 Raw END (empty = default) / Сырой END (пусто = по умолчанию)
# @param $7 Raw STEP (empty = 1) / Сырой STEP (пусто = 1)
# @return 0 ok, 1 invalid STEP or index (not an integer, or STEP = 0)
bs::__slice_bounds() {
  local -rn __b_start="${1:?output var name required}"
  local -rn __b_end="${2:?output var name required}"
  local -rn __b_step="${3:?output var name required}"
  local -ri __b_len="${4:?length required}"
  local -r __b_raw_start="${5-}" __b_raw_end="${6-}" __b_raw_step="${7-}"

  local __b_step_val=1
  if is::not_empty "${__b_raw_step}"; then
    [[ "${__b_raw_step}" =~ ^-?[0-9]+$ ]] || return 1
    (( __b_raw_step != 0 )) || return 1
    __b_step_val="${__b_raw_step}"
  fi
  __b_step="${__b_step_val}"

  local __b_start_val __b_end_val
  if (( __b_step_val > 0 )); then
    if is::empty "${__b_raw_start}"; then
      __b_start_val=0
    else
      __b_start_val="${__b_raw_start}"
      [[ "${__b_start_val}" =~ ^-?[0-9]+$ ]] || return 1
      (( __b_start_val < 0 )) && __b_start_val=$(( __b_len + __b_start_val ))
      (( __b_start_val < 0 )) && __b_start_val=0
      (( __b_start_val > __b_len )) && __b_start_val="${__b_len}"
    fi
    if is::empty "${__b_raw_end}"; then
      __b_end_val="${__b_len}"
    else
      __b_end_val="${__b_raw_end}"
      [[ "${__b_end_val}" =~ ^-?[0-9]+$ ]] || return 1
      (( __b_end_val < 0 )) && __b_end_val=$(( __b_len + __b_end_val ))
      (( __b_end_val < 0 )) && __b_end_val=0
      (( __b_end_val > __b_len )) && __b_end_val="${__b_len}"
    fi
  else
    if is::empty "${__b_raw_start}"; then
      __b_start_val=$(( __b_len - 1 ))
    else
      __b_start_val="${__b_raw_start}"
      [[ "${__b_start_val}" =~ ^-?[0-9]+$ ]] || return 1
      (( __b_start_val < 0 )) && __b_start_val=$(( __b_len + __b_start_val ))
      (( __b_start_val < -1 )) && __b_start_val=-1
      (( __b_start_val > __b_len - 1 )) && __b_start_val=$(( __b_len - 1 ))
    fi
    if is::empty "${__b_raw_end}"; then
      __b_end_val=-1
    else
      __b_end_val="${__b_raw_end}"
      [[ "${__b_end_val}" =~ ^-?[0-9]+$ ]] || return 1
      (( __b_end_val < 0 )) && __b_end_val=$(( __b_len + __b_end_val ))
      (( __b_end_val < -1 )) && __b_end_val=-1
      (( __b_end_val > __b_len - 1 )) && __b_end_val=$(( __b_len - 1 ))
    fi
  fi

  __b_start="${__b_start_val}"
  __b_end="${__b_end_val}"
}

# @description Strict bounds validation: out-of-range is an error, not a clamp.
# @description Строгая проверка границ: выход за диапазон — ошибка, а не кламп.
#   Shared by arr::slice_strict and str::slice_strict. Private.
# @param $1 Length of the collection / Длина коллекции
# @param $2 Raw START (empty = ok) / Сырой START (пусто = ок)
# @param $3 Raw END (empty = ok) / Сырой END (пусто = ок)
# @param $4 Raw STEP (empty = 1) / Сырой STEP (пусто = 1)
# @return 0 in bounds, 1 out of bounds or invalid
bs::__slice_strict_check() {
  local -ri __b_len="${1:?length required}"
  local -r __b_raw_start="${2-}" __b_raw_end="${3-}" __b_raw_step="${4-1}"

  if is::not_empty "${__b_raw_step}"; then
    [[ "${__b_raw_step}" =~ ^-?[0-9]+$ ]] || return 1
    (( __b_raw_step != 0 )) || return 1
  fi

  local -i __b_start_max=$(( __b_len - 1 ))
  local -i __b_end_max
  if [[ "${__b_raw_step}" == -* ]]; then
    __b_end_max=$(( __b_len - 1 ))
  else
    __b_end_max="${__b_len}"
  fi

  if is::not_empty "${__b_raw_start}"; then
    [[ "${__b_raw_start}" =~ ^-?[0-9]+$ ]] || return 1
    if (( __b_raw_start >= 0 )); then
      (( __b_raw_start > __b_start_max )) && return 1
    else
      (( __b_raw_start < -__b_len )) && return 1
    fi
  fi
  if is::not_empty "${__b_raw_end}"; then
    [[ "${__b_raw_end}" =~ ^-?[0-9]+$ ]] || return 1
    if (( __b_raw_end >= 0 )); then
      (( __b_raw_end > __b_end_max )) && return 1
    else
      (( __b_raw_end < -__b_len )) && return 1
    fi
  fi
  return 0
}

# @description Slice an array into another array (Python-style).
# @description Слайс массива в другой массив (в стиле Python).
#   `arr::slice src out` copies; `src out 1 4` takes elements 1..3;
#   `src out -3` takes the last 3; `src out "" "" -1` reverses.
#   If OUT is empty, elements are printed one per line (piping mode).
#   Если OUT пусто, элементы печатаются по одному на строку (режим пайпов).
# @param $1 Source array name / Имя исходного массива
# @param $2 Output array name (will be reset), or empty to print to stdout
#        Имя выходного массива (будет очищен), либо пусто для печати в stdout
# @param $3 [optional] START index, negative = from end, empty = 0
# @param $4 [optional] END index (exclusive), negative = from end, empty = end
# @param $5 [optional] STEP, non-zero integer, negative reverses
# @return 0 ok, 1 invalid STEP/index
# @example
#   arr::slice days weekdays 0 5        # first 5
#   arr::slice days weekend -2          # last 2
#   arr::slice days reversed "" "" -1   # full reverse
#   arr::slice days "" 1 4 | while read -r d; do ...; done
arr::slice() {
  local -rn __arr_src="${1:?source array name required}"
  local -r __sl_out="${2-}"
  local -r __sl_raw_start="${3-}" __sl_raw_end="${4-}" __sl_raw_step="${5-}"
  local -ri __sl_len="${#__arr_src[@]}"

  local __sl_start __sl_end __sl_step
  if ! bs::__slice_bounds __sl_start __sl_end __sl_step "${__sl_len}" \
       "${__sl_raw_start}" "${__sl_raw_end}" "${__sl_raw_step}"; then
    return 1
  fi

  local -i __sl_i
  if is::empty "${__sl_out}"; then
    if (( __sl_step > 0 )); then
      (( __sl_start >= __sl_end )) && return 0
      if (( __sl_step == 1 )); then
        printf '%s\n' "${__arr_src[@]:__sl_start:__sl_end - __sl_start}"
        return 0
      fi
      for (( __sl_i = __sl_start; __sl_i < __sl_end; __sl_i += __sl_step )); do
        printf '%s\n' "${__arr_src[__sl_i]}"
      done
    else
      (( __sl_start <= __sl_end )) && return 0
      for (( __sl_i = __sl_start; __sl_i > __sl_end; __sl_i += __sl_step )); do
        printf '%s\n' "${__arr_src[__sl_i]}"
      done
    fi
    return 0
  fi

  local -rn __arr_out="${__sl_out}"
  __arr_out=()
  if (( __sl_step > 0 )); then
    (( __sl_start >= __sl_end )) && return 0
    if (( __sl_step == 1 )); then
      __arr_out=("${__arr_src[@]:__sl_start:__sl_end - __sl_start}")
      return 0
    fi
    for (( __sl_i = __sl_start; __sl_i < __sl_end; __sl_i += __sl_step )); do
      __arr_out+=("${__arr_src[__sl_i]}")
    done
  else
    (( __sl_start <= __sl_end )) && return 0
    for (( __sl_i = __sl_start; __sl_i > __sl_end; __sl_i += __sl_step )); do
      __arr_out+=("${__arr_src[__sl_i]}")
    done
  fi
}

# @description Strict array slice: out-of-bounds START/END return 1 (no clamp).
# @description Строгий слайс массива: выход START/END за границы возвращает 1
#   (без клампинга). Same arguments as arr::slice.
# @return 0 ok, 1 invalid or out-of-bounds
# @example
#   arr::slice_strict days out 1 8    # 1 — только 7 элементов
arr::slice_strict() {
  local -rn __arr_src="${1:?source array name required}"
  bs::__slice_strict_check "${#__arr_src[@]}" "${3-}" "${4-}" "${5-}" || return 1
  arr::slice "$@"
}

# @description Strict string slice: out-of-bounds START/END return 1 (no clamp).
# @description Строгий слайс строки: выход START/END за границы возвращает 1
#   (без клампинга). Same arguments as str::slice.
# @return 0 ok, 1 invalid or out-of-bounds
# @example
#   str::slice_strict "abc" 1 9       # 1
str::slice_strict() {
  bs::__slice_strict_check "${#1}" "${2-}" "${3-}" "${4-}" || return 1
  str::slice "$@"
}

# @description Compute a string slice into a variable (no subshell).
# @description Вычислить слайс строки в переменную (без subshell).
#   Shared by str::slice and str::slice_to. Private, do not call directly.
# @param $1 Output variable name / Имя выходной переменной
# @param $2 String / Строка
# @param $3 [optional] START index, negative = from end, empty = 0
# @param $4 [optional] END index (exclusive), negative = from end, empty = end
# @param $5 [optional] STEP, non-zero integer, negative reverses
# @return 0 ok, 1 invalid STEP/index
bs::__slice_str() {
  local -rn __str_out="${1:?output var name required}"
  local -r __sl_str="${2:?string required}"
  local -r __sl_raw_start="${3-}" __sl_raw_end="${4-}" __sl_raw_step="${5-}"
  local -ri __sl_len="${#__sl_str}"

  local __sl_start __sl_end __sl_step
  if ! bs::__slice_bounds __sl_start __sl_end __sl_step "${__sl_len}" \
       "${__sl_raw_start}" "${__sl_raw_end}" "${__sl_raw_step}"; then
    return 1
  fi

  local -i __sl_i
  __str_out=""
  if (( __sl_step > 0 )); then
    (( __sl_start >= __sl_end )) && return 0
    if (( __sl_step == 1 )); then
      __str_out="${__sl_str:__sl_start:__sl_end - __sl_start}"
      return 0
    fi
    for (( __sl_i = __sl_start; __sl_i < __sl_end; __sl_i += __sl_step )); do
      __str_out+="${__sl_str:__sl_i:1}"
    done
  else
    (( __sl_start <= __sl_end )) && return 0
    for (( __sl_i = __sl_start; __sl_i > __sl_end; __sl_i += __sl_step )); do
      __str_out+="${__sl_str:__sl_i:1}"
    done
  fi
}

# @description Slice a string, printed to stdout (Python-style).
# @description Слайс строки, результат в stdout (в стиле Python).
#   `str::slice "hello" 1 4` -> "ell"; `str::slice "hello" -3` -> "llo";
#   `str::slice "hello" "" "" -1` -> "olleh".
# @param $1 String / Строка
# @param $2 [optional] START index, negative = from end, empty = 0
# @param $3 [optional] END index (exclusive), negative = from end, empty = end
# @param $4 [optional] STEP, non-zero integer, negative reverses
# @stdout the slice / результат слайса
# @return 0 ok, 1 invalid STEP/index
# @example
#   prefix="$(str::slice "${url}" 0 8)"
str::slice() {
  local __sl_result
  bs::__slice_str __sl_result "$@" || return 1
  printf '%s\n' "${__sl_result}"
}

# @description Slice a string into a variable (no subshell, faster on big strings).
# @description Слайс строки в переменную (без subshell, быстрее на больших строках).
# @param $1 Output variable name / Имя выходной переменной
# @param $2 String / Строка
# @param $3 [optional] START index, negative = from end, empty = 0
# @param $4 [optional] END index (exclusive), negative = from end, empty = end
# @param $5 [optional] STEP, non-zero integer, negative reverses
# @return 0 ok, 1 invalid STEP/index
# @example
#   str::slice_to prefix "${url}" 0 8
str::slice_to() {
  local -r __sl_out="${1:?output var name required}"
  shift
  bs::__slice_str "${__sl_out}" "$@" || return 1
}

# @description Split a string into chunks of N characters.
# @description Разбить строку на куски по N символов.
# @param $1 String / Строка
# @param $2 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @param $3 Chunk size, positive integer / Размер куска, целое число > 0
# @return 0 ok, 1 invalid size
# @example
#   str::chunk "abcdef" parts 2     # parts = (ab cd ef)
str::chunk() {
  local -rn __ch_out="${2:?output array name required}"
  local -r __sl_str="${1:?string required}"
  local -r __sl_n="${3:?chunk size required}"
  [[ "${__sl_n}" =~ ^[0-9]+$ ]] || return 1
  (( __sl_n > 0 )) || return 1

  local -ri __sl_len="${#__sl_str}"
  local -i __sl_i
  __ch_out=()
  for (( __sl_i = 0; __sl_i < __sl_len; __sl_i += __sl_n )); do
    __ch_out+=("${__sl_str:__sl_i:__sl_n}")
  done
}

# @description Reversed copy of an array / Развёрнутая копия массива.
# @param $1 Source array name / Имя исходного массива
# @param $2 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @example
#   arr::reverse history recent
arr::reverse() {
  arr::slice "${1:?source array name required}" "${2:?output array name required}" "" "" -1
}

# @description Reversed string, printed to stdout / Развёрнутая строка в stdout.
# @param $1 String / Строка
# @stdout reversed string / развёрнутая строка
# @example
#   echo "$(str::reverse "abc")"   # cba
str::reverse() {
  str::slice "${1:?string required}" "" "" -1
}

# @description Element at an index, printed to stdout (Python: a[idx]).
# @description Элемент по индексу, результат в stdout (Python: a[idx]).
#   Negative indices count from the end (a[-1] = last element).
# @param $1 Array name / Имя массива
# @param $2 Index, negative = from end / Индекс, отрицательный = с конца
# @stdout the element / элемент
# @return 0 ok, 1 index out of bounds or not an integer
# @example
#   last="$(arr::get names -1)"
arr::get() {
  local -rn __arr_ref="${1:?array name required}"
  local -r __sl_idx="${2:?index required}"
  [[ "${__sl_idx}" =~ ^-?[0-9]+$ ]] || return 1

  local -ri __sl_len="${#__arr_ref[@]}"
  local __sl_i
  if (( __sl_idx < 0 )); then
    (( __sl_idx < -__sl_len )) && return 1
    __sl_i=$(( __sl_len + __sl_idx ))
  else
    (( __sl_idx >= __sl_len )) && return 1
    __sl_i="${__sl_idx}"
  fi
  printf '%s\n' "${__arr_ref[__sl_i]}"
}

# @description First element, printed to stdout / Первый элемент в stdout.
# @param $1 Array name / Имя массива
# @return 0 ok, 1 empty array
arr::first() {
  arr::get "${1:?array name required}" 0
}

# @description Last element, printed to stdout / Последний элемент в stdout.
# @param $1 Array name / Имя массива
# @return 0 ok, 1 empty array
arr::last() {
  arr::get "${1:?array name required}" -1
}

# @description First N elements (head) / Первые N элементов (head).
# @param $1 Source array name / Имя исходного массива
# @param $2 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @param $3 Count, non-negative integer / Количество, целое число >= 0
# @return 0 ok, 1 invalid count
# @example
#   arr::head logs recent 10
arr::head() {
  local -r __sl_n="${3:?count required}"
  [[ "${__sl_n}" =~ ^[0-9]+$ ]] || return 1
  arr::slice "${1:?source array name required}" "${2:?output array name required}" 0 "${__sl_n}"
}

# @description Last N elements (tail) / Последние N элементов (tail).
# @param $1 Source array name / Имя исходного массива
# @param $2 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @param $3 Count, non-negative integer / Количество, целое число >= 0
# @return 0 ok, 1 invalid count
# @example
#   arr::tail logs last_lines 50
arr::tail() {
  local -r __sl_n="${3:?count required}"
  [[ "${__sl_n}" =~ ^[0-9]+$ ]] || return 1
  if (( __sl_n == 0 )); then
    arr::slice "${1:?source array name required}" "${2:?output array name required}" 0 0
    return 0
  fi
  arr::slice "${1}" "${2}" "-${__sl_n}"
}

# @description All elements except the first N (drop).
# @description Все элементы, кроме первых N (drop).
# @param $1 Source array name / Имя исходного массива
# @param $2 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @param $3 Count, non-negative integer / Количество, целое число >= 0
# @return 0 ok, 1 invalid count
# @example
#   arr::drop args rest 1     # skip the program name
arr::drop() {
  local -r __sl_n="${3:?count required}"
  [[ "${__sl_n}" =~ ^[0-9]+$ ]] || return 1
  arr::slice "${1:?source array name required}" "${2:?output array name required}" "${__sl_n}"
}

# @description Remove a range from an array in place (Python: del a[1:4]).
# @description Удалить диапазон из массива на месте (Python: del a[1:4]).
# @param $1 Array name (modified in place) / Имя массива (изменяется на месте)
# @param $2 [optional] START index, negative = from end, empty = 0
# @param $3 [optional] END index (exclusive), negative = from end, empty = end
# @return 0 ok, 1 invalid START/END
# @example
#   arr::cut history 0 10      # forget the oldest 10
arr::cut() {
  local -rn __arr_ref="${1:?array name required}"
  local -r __sl_raw_start="${2-}" __sl_raw_end="${3-}"
  local -ri __sl_len="${#__arr_ref[@]}"

  local __sl_start __sl_end __sl_step
  bs::__slice_bounds __sl_start __sl_end __sl_step "${__sl_len}" \
    "${__sl_raw_start}" "${__sl_raw_end}" 1 || return 1

  local -a __sl_new=()
  local -i __sl_i
  for (( __sl_i = 0; __sl_i < __sl_start; __sl_i++ )); do
    __sl_new+=("${__arr_ref[__sl_i]}")
  done
  for (( __sl_i = __sl_end; __sl_i < __sl_len; __sl_i++ )); do
    __sl_new+=("${__arr_ref[__sl_i]}")
  done
  __arr_ref=("${__sl_new[@]}")
}

# @description Replace a range in an array with new elements in place
# @description Заменить диапазон массива новыми элементами на месте
#   (Python: a[1:4] = [...]; splice NAME 0 0 x = insert at front).
# @param $1 Array name (modified in place) / Имя массива (изменяется на месте)
# @param $2 START index, negative = from end / Индекс START, отрицательный = с конца
# @param $3 END index (exclusive), negative = from end, empty = end
#        Индекс END (не включается), отрицательный = с конца, пусто = конец
# @param $@ [optional] Replacement elements / Заменяющие элементы
# @return 0 ok, 1 invalid START/END
# @example
#   arr::splice words 1 2 "а" "б"
arr::splice() {
  local -rn __arr_ref="${1:?array name required}"
  local -r __sl_raw_start="${2:?start index required}"
  local -r __sl_raw_end="${3-}"
  if (( $# > 3 )); then
    shift 3
  else
    set --
  fi
  local -ri __sl_len="${#__arr_ref[@]}"

  local __sl_start __sl_end __sl_step
  bs::__slice_bounds __sl_start __sl_end __sl_step "${__sl_len}" \
    "${__sl_raw_start}" "${__sl_raw_end}" 1 || return 1

  local -a __sl_new=()
  local -i __sl_i
  for (( __sl_i = 0; __sl_i < __sl_start; __sl_i++ )); do
    __sl_new+=("${__arr_ref[__sl_i]}")
  done
  local __sl_elem
  for __sl_elem in "$@"; do
    __sl_new+=("${__sl_elem}")
  done
  for (( __sl_i = __sl_end; __sl_i < __sl_len; __sl_i++ )); do
    __sl_new+=("${__arr_ref[__sl_i]}")
  done
  __arr_ref=("${__sl_new[@]}")
}

# @description Replace an array with its own slice in place (Python: a = a[1:4]).
# @description Заменить массив его собственным слайсом (Python: a = a[1:4]).
# @param $1 Array name (modified in place) / Имя массива (изменяется на месте)
# @param $2 [optional] START index, negative = from end, empty = 0
# @param $3 [optional] END index (exclusive), negative = from end, empty = end
# @param $4 [optional] STEP, non-zero integer, negative reverses
# @return 0 ok, 1 invalid STEP/index
# @example
#   arr::slice_inplace queue 1 -1
arr::slice_inplace() {
  local -rn __self="${1:?array name required}"
  local -r __sl_raw_start="${2-}" __sl_raw_end="${3-}" __sl_raw_step="${4-}"
  local -ri __sl_len="${#__self[@]}"

  local __sl_start __sl_end __sl_step
  bs::__slice_bounds __sl_start __sl_end __sl_step "${__sl_len}" \
    "${__sl_raw_start}" "${__sl_raw_end}" "${__sl_raw_step}" || return 1

  local -a __sl_new=()
  local -i __sl_i
  if (( __sl_step > 0 )); then
    (( __sl_start >= __sl_end )) && { __self=(); return 0; }
    if (( __sl_step == 1 )); then
      __self=("${__self[@]:__sl_start:__sl_end - __sl_start}")
      return 0
    fi
    for (( __sl_i = __sl_start; __sl_i < __sl_end; __sl_i += __sl_step )); do
      __sl_new+=("${__self[__sl_i]}")
    done
  else
    (( __sl_start <= __sl_end )) && { __self=(); return 0; }
    for (( __sl_i = __sl_start; __sl_i > __sl_end; __sl_i += __sl_step )); do
      __sl_new+=("${__self[__sl_i]}")
    done
  fi
  __self=("${__sl_new[@]}")
}

# @description Number of keys in a map / Число ключей в map.
# @param $1 Map name / Имя map
# @stdout key count / количество ключей
map::count() {
  local -rn __map_ref="${1:?map name required}"
  printf '%s\n' "${#__map_ref[@]}"
}

# @description All keys of a map as an array (iteration order, NOT sorted).
# @description Все ключи map массивом (порядок итерации, НЕ отсортирован).
#   Bash does not guarantee map iteration order — do not rely on it.
# @param $1 Map name / Имя map
# @param $2 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @example
#   map::keys config all_keys
map::keys() {
  local -rn __map_ref="${1:?map name required}"
  local -rn __map_out="${2:?output array name required}"
  __map_out=("${!__map_ref[@]}")
}

# @description All values of a map as an array (same order as map::keys).
# @description Все значения map массивом (в том же порядке, что map::keys).
# @param $1 Map name / Имя map
# @param $2 Output array name (will be reset) / Имя выходного массива (будет очищен)
map::values() {
  local -rn __map_ref="${1:?map name required}"
  local -rn __map_out="${2:?output array name required}"
  __map_out=("${__map_ref[@]}")
}

# @description Slice of map entries into another map (Python: dict(list(m.items())[s:e])).
# @description Слайс записей map в другой map (Python: dict(list(m.items())[s:e])).
#   Order follows map iteration order, which Bash does NOT guarantee — for a
#   deterministic order use map::slice_by_keys. OUT must be declared -A.
#   Порядок — порядок итерации map, который Bash НЕ гарантирует; для
#   детерминированного порядка используйте map::slice_by_keys.
#   OUT должен быть объявлен как -A.
# @param $1 Source map name / Имя исходного map
# @param $2 Output map name (must be declared -A, will be reset)
#        Имя выходного map (должен быть объявлен -A, будет очищен)
# @param $3 [optional] START index (in iteration order), negative = from end
# @param $4 [optional] END index (exclusive), negative = from end
# @return 0 ok, 1 invalid START/END or OUT is not an associative array
# @example
#   declare -A sub
#   map::slice config sub 0 5
map::slice() {
  local -rn __map_src="${1:?source map name required}"
  local -r __sl_out="${2:?output map name required}"
  local -r __sl_raw_start="${3-}" __sl_raw_end="${4-}"

  declare -g -A "${__sl_out}" 2>/dev/null || return 1
  local -rn __map_out="${__sl_out}"
  local -ri __sl_len="${#__map_src[@]}"

  local __sl_start __sl_end __sl_step
  bs::__slice_bounds __sl_start __sl_end __sl_step "${__sl_len}" \
    "${__sl_raw_start}" "${__sl_raw_end}" 1 || return 1

  local -a __sl_keys=("${!__map_src[@]}")
  local -i __sl_i
  local __sl_key
  __map_out=()
  for (( __sl_i = __sl_start; __sl_i < __sl_end; __sl_i++ )); do
    __sl_key="${__sl_keys[__sl_i]}"
    __map_out["${__sl_key}"]="${__map_src["${__sl_key}"]}"
  done
}

# @description Deterministic map slice: copy given keys (in given order).
# @description Детерминированный слайс map: скопировать перечисленные ключи
#   (в переданном порядке). Unknown keys are silently skipped.
# @param $1 Source map name / Имя исходного map
# @param $2 Output map name (must be declared -A, will be reset)
#        Имя выходного map (должен быть объявлен -A, будет очищен)
# @param $@ Keys to copy / Ключи для копирования
# @return 0 ok, 1 OUT is not an associative array
# @example
#   map::slice_by_keys config sub host port
map::slice_by_keys() {
  local -rn __map_src="${1:?source map name required}"
  local -r __sl_out="${2:?output map name required}"
  shift 2

  declare -g -A "${__sl_out}" 2>/dev/null || return 1
  local -rn __map_out="${__sl_out}"
  __map_out=()
  local __sl_key
  for __sl_key in "$@"; do
    if [[ -v __map_src["${__sl_key}"] ]]; then
      __map_out["${__sl_key}"]="${__map_src["${__sl_key}"]}"
    fi
  done
}

# @description Pick given keys into a new map (TypeScript: Pick<T, K>).
# @description Выбрать перечисленные ключи в новый map (TypeScript: Pick<T, K>).
#   Alias of map::slice_by_keys. Unknown keys are silently skipped.
# @param $1 Source map name / Имя исходного map
# @param $2 Output map name (may be created) / Имя выходного map (может быть создан)
# @param $@ Keys to pick / Ключи для выбора
# @example
#   map::pick cfg public host port
map::pick() {
  map::slice_by_keys "$@"
}

# @description All keys except the listed ones (TypeScript: Omit<T, K>).
# @description Все ключи, кроме перечисленных (TypeScript: Omit<T, K>).
# @param $1 Source map name / Имя исходного map
# @param $2 Output map name (may be created) / Имя выходного map (может быть создан)
# @param $@ Keys to omit / Ключи для исключения
# @return 0 ok, 1 output cannot be an associative array
# @example
#   map::omit cfg internal secret token
map::omit() {
  local -rn __map_src="${1:?source map name required}"
  local -r __sl_out="${2:?output map name required}"
  shift 2

  declare -g -A "${__sl_out}" 2>/dev/null || return 1
  local -rn __map_out="${__sl_out}"
  local -A __map_rm=()
  local __sl_key
  for __sl_key in "$@"; do
    __map_rm["${__sl_key}"]=1
  done
  __map_out=()
  for __sl_key in "${!__map_src[@]}"; do
    [[ -v __map_rm["${__sl_key}"] ]] || __map_out["${__sl_key}"]="${__map_src["${__sl_key}"]}"
  done
}

# @description Unified slice: works on arrays, strings and maps by type.
# @description Унифицированный слайс: работает с массивами, строками и map
#   в зависимости от типа (bs::type_of). Одна команда вместо трёх.
#   For maps STEP is ignored; for strings OUT may be empty to print to stdout.
#   Для map STEP игнорируется; для строк OUT может быть пустым для печати.
# @param $1 Variable name (array/string/map) / Имя переменной (массив/строка/map)
# @param $2 Output variable name (array: empty = print; string: may be empty;
#        map: must be declared -A) / Имя выходной переменной
# @param $3 [optional] START index, negative = from end, empty = 0
# @param $4 [optional] END index (exclusive), negative = from end, empty = end
# @param $5 [optional] STEP, non-zero integer, negative reverses
# @return 0 ok, 1 invalid type/indices
# @example
#   bs::slice args rest 1        # array → slice
#   bs::slice host part 0 5      # string → slice
bs::slice() {
  local -r __sl_name="${1:?variable name required}"
  local -r __sl_out="${2-}"
  shift 2

  case "$(bs::type_of "${__sl_name}")" in
    array)
      arr::slice "${__sl_name}" "${__sl_out}" "$@"
      ;;
    string)
      if is::empty "${__sl_out}"; then
        str::slice "${!__sl_name}" "$@"
      else
        str::slice_to "${__sl_out}" "${!__sl_name}" "$@"
      fi
      ;;
    map)
      if is::empty "${__sl_out}"; then
        printf '%s\n' "bs::slice: map requires an output map name" >&2
        return 1
      fi
      map::slice "${__sl_name}" "${__sl_out}" "$@"
      ;;
    *)
      printf '%s\n' "bs::slice: unsupported type for '${__sl_name}'" >&2
      return 1
      ;;
  esac
}

# ==========================================
# Iterators / Итераторы
#
# Callback-based transformations (Python comprehensions, Rust iterators):
# the callback is passed BY NAME and its stdout is captured as the result.
# Callbacks must print the result and return 0; a non-zero return aborts.
# SRC and OUT must be different arrays.
# Преобразования на колбэках (Python comprehensions, итераторы Rust):
# колбэк передаётся ПО ИМЕНИ, его stdout захватывается как результат.
# Колбэк должен печатать результат и возвращать 0; ненулевой код прерывает.
# SRC и OUT должны быть разными массивами.
# ==========================================

# @description Map each element through a callback (Python: [f(x) for x in a]).
# @description Преобразовать каждый элемент колбэком (Python: [f(x) for x in a]).
# @param $1 Source array name / Имя исходного массива
# @param $2 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @param $3 Callback function name (prints result) / Имя колбэка (печатает результат)
# @param $@ [optional] Extra arguments passed to the callback
#        Дополнительные аргументы, передаваемые колбэку
# @return 0 ok, 1 callback missing/failed
# @example
#   double() { printf '%s\n' "$(( $1 * 2 ))"; }
#   arr::map nums doubled double
arr::map() {
  local -rn __arr_src="${1:?source array name required}"
  local -rn __arr_out="${2:?output array name required}"
  local -r __arr_fn="${3:?callback function name required}"
  is::function "${__arr_fn}" || return 1
  shift 3

  local __arr_elem __arr_mapped
  __arr_out=()
  for __arr_elem in "${__arr_src[@]}"; do
    __arr_mapped="$("${__arr_fn}" "${__arr_elem}" "$@")" || return 1
    __arr_out+=("${__arr_mapped}")
  done
}

# @description Keep elements where the predicate returns 0 (Python: [x for x in a if p(x)]).
# @description Оставить элементы, где предикат возвращает 0
#   (Python: [x for x in a if p(x)]).
# @param $1 Source array name / Имя исходного массива
# @param $2 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @param $3 Predicate function name / Имя функции-предиката
# @param $@ [optional] Extra arguments passed to the predicate
#        Дополнительные аргументы, передаваемые предикату
# @return 0 ok, 1 predicate missing
# @example
#   is_even() { (( $1 % 2 == 0 )); }
#   arr::filter nums evens is_even
arr::filter() {
  local -rn __arr_src="${1:?source array name required}"
  local -rn __arr_out="${2:?output array name required}"
  local -r __arr_pred="${3:?predicate function name required}"
  is::function "${__arr_pred}" || return 1
  shift 3

  local __arr_elem
  __arr_out=()
  for __arr_elem in "${__arr_src[@]}"; do
    if "${__arr_pred}" "${__arr_elem}" "$@" >/dev/null 2>&1; then
      __arr_out+=("${__arr_elem}")
    fi
  done
}

# @description Fold the array through a binary callback (Python: functools.reduce).
# @description Свёртка массива бинарным колбэком (Python: functools.reduce).
#   Callback receives (accumulator, element) and prints the new accumulator.
#   Колбэк получает (аккумулятор, элемент) и печатает новый аккумулятор.
# @param $1 Source array name / Имя исходного массива
# @param $2 Initial accumulator / Начальный аккумулятор
# @param $3 Callback function name / Имя колбэка
# @param $@ [optional] Extra arguments passed to the callback
#        Дополнительные аргументы, передаваемые колбэку
# @stdout final accumulator / итоговый аккумулятор
# @return 0 ok, 1 callback missing/failed
# @example
#   concat() { printf '%s' "${1}${2}"; }
#   arr::reduce words "" concat
arr::reduce() {
  local -rn __arr_src="${1:?source array name required}"
  (( $# >= 2 )) || return 1
  local -r __arr_acc="${2-}"
  local -r __arr_fn="${3:?callback function name required}"
  is::function "${__arr_fn}" || return 1
  shift 3

  local __arr_elem __arr_result="${__arr_acc}"
  for __arr_elem in "${__arr_src[@]}"; do
    __arr_result="$("${__arr_fn}" "${__arr_result}" "${__arr_elem}" "$@")" || return 1
  done
  printf '%s\n' "${__arr_result}"
}

# @description First element matching a predicate (Python: next(x for x in a if p(x))).
# @description Первый элемент, подходящий под предикат
#   (Python: next(x for x in a if p(x))).
# @param $1 Source array name / Имя исходного массива
# @param $2 Predicate function name / Имя функции-предиката
# @param $@ [optional] Extra arguments passed to the predicate
#        Дополнительные аргументы, передаваемые предикату
# @stdout the first match / первый подходящий элемент
# @return 0 found, 1 no match or predicate missing
# @example
#   arr::find services is_running
arr::find() {
  local -rn __arr_src="${1:?source array name required}"
  local -r __arr_pred="${2:?predicate function name required}"
  is::function "${__arr_pred}" || return 1
  shift 2

  local __arr_elem
  for __arr_elem in "${__arr_src[@]}"; do
    if "${__arr_pred}" "${__arr_elem}" "$@" >/dev/null 2>&1; then
      printf '%s\n' "${__arr_elem}"
      return 0
    fi
  done
  return 1
}

# @description Index of the first exact match (Python: a.index(x)).
# @description Индекс первого точного совпадения (Python: a.index(x)).
# @param $1 Source array name / Имя исходного массива
# @param $2 Needle / Искомый элемент
# @stdout index / индекс
# @return 0 found, 1 not found
# @example
#   idx="$(arr::index_of users admin)"
arr::index_of() {
  local -rn __arr_src="${1:?source array name required}"
  local -r __arr_needle="${2:?needle required}"
  local -i __arr_i=0
  local __arr_elem
  for __arr_elem in "${__arr_src[@]}"; do
    if [[ "${__arr_elem}" == "${__arr_needle}" ]]; then
      printf '%s\n' "${__arr_i}"
      return 0
    fi
    __arr_i=$(( __arr_i + 1 ))
  done
  return 1
}

# @description Generate a numeric sequence (Python: range()).
# @description Сгенерировать числовую последовательность (Python: range()).
#   END is exclusive, negative STEP descends. Replaces `seq` with no forks.
#   END не включается, отрицательный STEP убывает. Заменяет `seq` без форков.
# @param $1 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @param $2 [optional] START, default 0 / Начало, по умолчанию 0
# @param $3 END (exclusive) / Конец (не включается)
# @param $4 [optional] STEP, non-zero integer, default 1 / Шаг, целое != 0
# @return 0 ok, 1 invalid argument
# @example
#   arr::range ids 1 11        # 1 2 ... 10
#   arr::range rev 5 0 -1      # 5 4 3 2 1
arr::range() {
  local -rn __arr_out="${1:?output array name required}"
  local __arr_start="${2-0}" __arr_end="${3:?end index required}" __arr_step="${4-1}"
  is::empty "${__arr_start}" && __arr_start=0
  is::empty "${__arr_step}" && __arr_step=1
  [[ "${__arr_start}" =~ ^-?[0-9]+$ ]] || return 1
  [[ "${__arr_end}" =~ ^-?[0-9]+$ ]] || return 1
  [[ "${__arr_step}" =~ ^-?[0-9]+$ ]] || return 1
  (( __arr_step != 0 )) || return 1

  local -i __arr_i
  __arr_out=()
  if (( __arr_step > 0 )); then
    for (( __arr_i = __arr_start; __arr_i < __arr_end; __arr_i += __arr_step )); do
      __arr_out+=("${__arr_i}")
    done
  else
    for (( __arr_i = __arr_start; __arr_i > __arr_end; __arr_i += __arr_step )); do
      __arr_out+=("${__arr_i}")
    done
  fi
}

# @description Unpack first elements into named variables (Python: a, b, c = items).
# @description Распаковать первые элементы в именованные переменные
#   (Python: a, b, c = items). Missing elements become empty strings.
#   Отсутствующие элементы становятся пустыми строками.
# @param $1 Source array name / Имя исходного массива
# @param $@ Output variable names (may be created) / Имена выходных переменных
# @example
#   arr::unpack line host port proto
arr::unpack() {
  local -rn __arr_src="${1:?source array name required}"
  shift
  local -i __arr_i=0
  local __arr_var
  for __arr_var in "$@"; do
    local -n __unp_ref="${__arr_var}"
    if (( __arr_i < ${#__arr_src[@]} )); then
      __unp_ref="${__arr_src[__arr_i]}"
    else
      __unp_ref=""
    fi
    __arr_i=$(( __arr_i + 1 ))
  done
}

# @description Split an array into fixed-size chunks (Python: batched(a, n)).
# @description Разбить массив на куски фиксированного размера
#   (Python: batched(a, n)). Chunk values are elements joined by newlines;
#   use arr::from_lines or utils::split to unpack a chunk back.
#   Значения кусков — элементы, склеенные переводами строк; чтобы вернуть
#   кусок в массив, используйте arr::from_lines или utils::split.
# @param $1 Source array name / Имя исходного массива
# @param $2 Output map name (may be created), key = chunk index
#        Имя выходного map (может быть создан), ключ = номер куска
# @param $3 Chunk size, positive integer / Размер куска, целое число > 0
# @return 0 ok, 1 invalid size or output cannot be a map
# @example
#   declare -A batches
#   arr::chunk tasks batches 10
#   for i in "${!batches[@]}"; do echo "batch $i"; done
arr::chunk() {
  local -rn __arr_src="${1:?source array name required}"
  local -r __arr_out_name="${2:?output map name required}"
  local -r __arr_n="${3:?chunk size required}"
  [[ "${__arr_n}" =~ ^[0-9]+$ ]] || return 1
  (( __arr_n > 0 )) || return 1
  declare -g -A "${__arr_out_name}" 2>/dev/null || return 1
  local -rn __arr_chunks="${__arr_out_name}"

  local -ri __arr_len="${#__arr_src[@]}"
  local -i __arr_i __arr_chunk
  local __arr_line
  __arr_chunks=()
  (( __arr_len == 0 )) && return 0

  __arr_chunk=0
  __arr_line="${__arr_src[0]}"
  for (( __arr_i = 1; __arr_i < __arr_len; __arr_i++ )); do
    if (( __arr_i % __arr_n == 0 )); then
      __arr_chunks["${__arr_chunk}"]="${__arr_line}"
      __arr_chunk=$(( __arr_i / __arr_n ))
      __arr_line="${__arr_src[__arr_i]}"
    else
      __arr_line+=$'\n'"${__arr_src[__arr_i]}"
    fi
  done
  __arr_chunks["${__arr_chunk}"]="${__arr_line}"
}

# @description Call a callback for every element (Python: for x in a).
# @description Вызвать колбэк для каждого элемента (Python: for x in a).
#   For side effects only: callback output is NOT captured.
#   Только для побочных эффектов: вывод колбэка не захватывается.
# @param $1 Source array name / Имя исходного массива
# @param $2 Callback function name / Имя колбэка
# @param $@ [optional] Extra arguments passed to the callback
#        Дополнительные аргументы, передаваемые колбэку
# @return 0 ok, 1 callback missing/failed
# @example
#   log_each() { log::info "item: $1"; }
#   arr::each services log_each
arr::each() {
  local -rn __arr_ref="${1:?array name required}"
  local -r __arr_fn="${2:?callback function name required}"
  is::function "${__arr_fn}" || return 1
  shift 2
  local __arr_elem
  for __arr_elem in "${__arr_ref[@]}"; do
    "${__arr_fn}" "${__arr_elem}" "$@" || return 1
  done
}

# @description Call a callback for every key/value pair (Python: for k, v in m.items()).
# @description Вызвать колбэк для каждой пары ключ/значение
#   (Python: for k, v in m.items()). Callback receives (key, value, extra...).
#   Колбэк получает (ключ, значение, доп...). Output is NOT captured.
# @param $1 Source map name / Имя исходного map
# @param $2 Callback function name / Имя колбэка
# @param $@ [optional] Extra arguments / Дополнительные аргументы
# @return 0 ok, 1 callback missing/failed
# @example
#   map::each my_config my::process_entry
map::each() {
  local -rn __map_ref="${1:?map name required}"
  local -r __map_fn="${2:?callback function name required}"
  is::function "${__map_fn}" || return 1
  shift 2
  local __map_key
  for __map_key in "${!__map_ref[@]}"; do
    "${__map_fn}" "${__map_key}" "${__map_ref["${__map_key}"]}" "$@" || return 1
  done
}

# @description Concatenate arrays into one (JS: [...a, ...b, ...c]).
# @description Склеить массивы в один (JS: [...a, ...b, ...c]).
# @param $1 Output array name (will be reset) / Имя выходного массива (будет очищен)
# @param $@ Source array names (may be zero) / Имена исходных массивов (может быть ноль)
# @example
#   arr::concat all args defaults
arr::concat() {
  local -rn __arr_out="${1:?output array name required}"
  shift
  __arr_out=()
  local __arr_src_name
  for __arr_src_name in "$@"; do
    local -n __arr_src="${__arr_src_name}"
    __arr_out+=("${__arr_src[@]}")
  done
}

# ==========================================
# Patterns / Паттерны
#
# Small conveniences that bring beloved language idioms to BS:
# decorators (Python @decorator), unwrap/expect (Rust Option/Result).
# Небольшие удобства, переносящие любимые идиомы языков в BS:
# декораторы (Python @decorator), unwrap/expect (Rust Option/Result).
# ==========================================

# @description Wrap a function so it is replaced by wrapper(original, args...).
# @description Обернуть функцию: она заменяется на wrapper(original, args...).
#   The original is preserved as bs::__orig_<name> (name with `::` -> `_`).
#   Исходная функция сохраняется как bs::__orig_<имя> (`::` -> `_`).
#   Python: @decorator. Wrapper's first argument is the original function name.
#   Python: @decorator. Первый аргумент wrapper — имя исходной функции.
# @param $1 Function name to wrap / Имя оборачиваемой функции
# @param $2 Wrapper function name / Имя функции-обёртки
# @return 0 ok, 1 invalid name or missing function
# @example
#   time_it() { local orig="$1"; shift; local t="$(utils::now_ms)"; "$orig" "$@"; echo "took $(( $(utils::now_ms) - t )) ms" >&2; }
#   bs::decorate my::slow time_it
bs::decorate() {
  local -r __dec_fn="${1:?function name required}" __dec_wrapper="${2:?wrapper name required}"
  [[ "${__dec_fn}" =~ ^[a-zA-Z0-9_:]+$ ]] || return 1
  [[ "${__dec_wrapper}" =~ ^[a-zA-Z0-9_:]+$ ]] || return 1
  is::function "${__dec_fn}" || return 1
  is::function "${__dec_wrapper}" || return 1

  local -r __dec_orig="bs::__orig_${__dec_fn//::/_}"
  local __dec_def __dec_body
  __dec_def="$(declare -f "${__dec_fn}")" || return 1
  __dec_body="${__dec_def#*\{}"
  __dec_body="${__dec_body%\}}"
  # shellcheck disable=SC2294
  eval "${__dec_orig}() { ${__dec_body} }" || return 1
  eval "${__dec_fn}() { ${__dec_wrapper} ${__dec_orig} \"\$@\"; }" || return 1
}

# @description Print a value or fail if it is empty (Rust: unwrap).
# @description Вывести значение или упасть, если оно пусто (Rust: unwrap).
# @param $1 Variable name / Имя переменной
# @param $2 [optional] Custom error message / Собственное сообщение об ошибке
# @stdout the value / значение
# @return 0 ok, 1 variable empty/unset
# @example
#   name="$(bs::unwrap user || error::throw "${E_ERROR}" "user required")"
bs::unwrap() {
  local -r __unw_name="${1:?variable name required}"
  local -r __unw_val="${!__unw_name:-}"
  if is::empty "${__unw_val}"; then
    printf '%s\n' "bs::unwrap: '${__unw_name}' is empty${2:+: ${2}}" >&2
    return 1
  fi
  printf '%s\n' "${__unw_val}"
}

# @description Print a value or fail with a message (Rust: expect).
# @description Вывести значение или упасть с сообщением (Rust: expect).
# @param $1 Variable name / Имя переменной
# @param $2 Message / Сообщение
# @stdout the value / значение
# @return 0 ok, 1 variable empty/unset
# @example
#   token="$(bs::expect api_token "API token is not configured")"
bs::expect() {
  local -r __unw_name="${1:?variable name required}"
  local -r __unw_msg="${2:?message required}"
  local -r __unw_val="${!__unw_name:-}"
  if is::empty "${__unw_val}"; then
    printf '%s\n' "bs::expect: '${__unw_name}': ${__unw_msg}" >&2
    return 1
  fi
  printf '%s\n' "${__unw_val}"
}

# ==========================================
# is:: — predicates for humans / предикаты для людей
#
# Дружелюбные замены для тестовых идиом bash: не нужно помнить,
# что -n значит "непусто", а -f — "обычный файл".
# Friendly replacements for bash test idioms: no need to remember
# that -n means "non-empty" and -f means "regular file".
# ==========================================

# @description Predicate: string is empty / Строка пуста. Replaces: [[ -z "$s" ]]
is::empty() {
  [[ -z "${1-}" ]]
}

# @description Predicate: string is not empty / Строка непуста.
#   Replaces: [[ -n "$s" ]]
is::not_empty() {
  [[ -n "${1-}" ]]
}

# @description Predicate: path exists / Путь существует. Replaces: [[ -e "$p" ]]
is::exists() {
  [[ -e "${1-}" ]]
}

# @description Predicate: regular file / Обычный файл. Replaces: [[ -f "$p" ]]
is::file() {
  [[ -f "${1-}" ]]
}

# @description Predicate: directory / Каталог. Replaces: [[ -d "$p" ]]
is::dir() {
  [[ -d "${1-}" ]]
}

# @description Predicate: symbolic link / Симлинк. Replaces: [[ -L "$p" ]]
is::symlink() {
  [[ -L "${1-}" ]]
}

# @description Predicate: file is not empty / Файл непустой. Replaces: [[ -s "$p" ]]
is::file_not_empty() {
  [[ -s "${1-}" ]]
}

# @description Predicate: executable / Исполняемый. Replaces: [[ -x "$p" ]]
is::executable() {
  [[ -x "${1-}" ]]
}

# @description Predicate: readable / Доступен на чтение. Replaces: [[ -r "$p" ]]
is::readable() {
  [[ -r "${1-}" ]]
}

# @description Predicate: writable / Доступен на запись. Replaces: [[ -w "$p" ]]
is::writable() {
  [[ -w "${1-}" ]]
}

# @description Predicate: string is a number / Строка — число.
#   Replaces: [[ "$s" =~ ^[0-9]+$ ]]
is::number() {
  [[ "${1-}" =~ ^[0-9]+$ ]]
}

# @description Predicate: command is available / Команда доступна.
#   Alias of utils::has. Replaces: command -v cmd >/dev/null 2>&1
is::command() {
  utils::has "${1:?command name required}"
}

# @description Predicate: function is defined / Функция определена.
#   Alias of bs::is_function.
is::function() {
  bs::is_function "${1:?function name required}"
}
