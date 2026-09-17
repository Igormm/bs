#!/usr/bin/env bs
# shellcheck shell=bash
# lib/data/regex.sh — регулярные выражения / regex module
# lib/data/regex.sh — регулярные выражения (ERE без зависимостей + PCRE)

# @depends core/lang, core/utils, core/errorhandler

# Source Guard
bs::guard "LIB_DATA_REGEX" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh" "../../core/utils.sh" "../../core/errorhandler.sh"

# ==========================================
# Regular expressions / Регулярные выражения
#
# Three engines, chosen by the function:
#   [[ =~ ]]      — POSIX ERE, zero forks, capture groups (regex::groups)
#   grep -E / -o  — ERE, all matches, line-based
#   grep -P       — PCRE (GNU grep, Linux): lookahead/lookbehind, \d, \w,
#                   lazy quantifiers, backrefs — requires GNU grep
# Engine selection:
#   regex::matches/find/count accept a trailing `--pcre` flag; without it
#   they use ERE, which works on any grep. Patterns in regex::groups and
#   regex::replace are POSIX ERE (bash =~ and sed -zE).
# Три движка по выбору функции:
#   [[ =~ ]]      — POSIX ERE, ноль форков, группы захвата (regex::groups)
#   grep -E / -o  — ERE, все совпадения, построчно
#   grep -P       — PCRE (GNU grep, Linux): lookahead/lookbehind, \d, \w,
#                   ленивые квантификаторы, обратные ссылки
# Выбор движка:
#   regex::matches/find/count принимают флаг `--pcre` в конце; без него —
#   ERE, работающий с любым grep. Паттерны в regex::groups и
#   regex::replace — POSIX ERE (bash =~ и sed -zE).
# ==========================================

# @description Predicate: string matches the pattern (Python: re.search).
# @description Предикат: строка соответствует паттерну (Python: re.search).
# @param $1 String / Строка
# @param $2 Pattern (ERE; PCRE with --pcre) / Паттерн (ERE; PCRE с --pcre)
# @param $3 [optional] --pcre / флаг PCRE
# @return 0 matches, 1 no match, 2 invalid pattern (ERE mode)
# @example
#   if regex::matches "${url}" '^https?://' ; then ...
#   if regex::matches "$line" '\d{4}-\d{2}-\d{2}' --pcre; then ...
regex::matches() {
  local -r __rg_str="${1-}" __rg_pattern="${2-}"
  if [[ "${3-}" == "--pcre" ]]; then
    is::command grep || return 1
    grep -Pq -- "${__rg_pattern}" <<< "${__rg_str}"
    return $?
  fi
  [[ "${__rg_str}" =~ ${__rg_pattern} ]]
  return $?
}

# @description Predicate alias of regex::matches / Предикат-алиас matches.
regex::test() {
  regex::matches "$@"
}

# @description All matches as lines (Python: re.findall).
# @description Все совпадения построчно (Python: re.findall).
#   Line-based: a match cannot span newlines (grep semantics). --pcre for
#   PCRE. Empty OUT prints matches to stdout.
#   Построчно: совпадение не может пересекать переводы строк (семантика
#   grep). --pcre для PCRE. Пустой OUT печатает совпадения в stdout.
# @param $1 String / Строка
# @param $2 Pattern / Паттерн
# @param $3 [optional] Output array name (will be reset) / Имя выходного массива
# @param $4 [optional] --pcre / флаг PCRE
# @return 0 ok (even with zero matches), 1 grep unavailable
# @example
#   regex::find "${log}" '\[ERROR\]' errors
regex::find() {
  local -r __rg_str="${1-}" __rg_pattern="${2-}"
  local -r __rg_out="${3-}" __rg_pcre="${4-}"
  local __rg_result=""
  if [[ "${__rg_pcre}" == "--pcre" ]]; then
    is::command grep || return 1
    __rg_result="$(grep -Po -- "${__rg_pattern}" <<< "${__rg_str}" 2>/dev/null || :)"
  else
    __rg_result="$(grep -Eo -- "${__rg_pattern}" <<< "${__rg_str}" 2>/dev/null || :)"
  fi
  if is::empty "${__rg_out}"; then
    is::empty "${__rg_result}" || printf '%s\n' "${__rg_result}"
    return 0
  fi
  local -rn __rg_ref="${__rg_out}"
  __rg_ref=()
  if is::not_empty "${__rg_result}"; then
    mapfile -t __rg_ref <<< "${__rg_result}"
  fi
}

# @description Number of matches (Python: len(re.findall)).
# @description Количество совпадений (Python: len(re.findall)).
# @param $1 String / Строка
# @param $2 Pattern / Паттерн
# @param $3 [optional] --pcre / флаг PCRE
# @stdout match count / число совпадений
# @return 0 ok, 1 grep unavailable
# @example
#   n="$(regex::count "${conf}" '^\s*\w+=')"
regex::count() {
  local -r __rg_str="${1-}" __rg_pattern="${2-}" __rg_pcre="${3-}"
  local __rg_n=""
  if [[ "${__rg_pcre}" == "--pcre" ]]; then
    is::command grep || return 1
    __rg_n="$(grep -Po -- "${__rg_pattern}" <<< "${__rg_str}" 2>/dev/null | wc -l || true)"
  else
    __rg_n="$(grep -Eo -- "${__rg_pattern}" <<< "${__rg_str}" 2>/dev/null | wc -l || true)"
  fi
  printf '%s\n' "${__rg_n}"
}

# @description Capture groups of the FIRST match into an array
# @description Группы захвата ПЕРВОГО совпадения в массив
#   (Python: re.search(...).groups()). Index 0 = whole match, 1..N = groups.
#   Uses bash [[ =~ ]] — POSIX ERE, zero forks, no --pcre.
# @param $1 String / Строка
# @param $2 Pattern (ERE) / Паттерн (ERE)
# @param $3 Output array name (will be reset) / Имя выходного массива
# @return 0 matched, 1 no match
# @example
#   regex::groups "${ver}" 'v([0-9]+)\.([0-9]+)' parts
#   major="${parts[1]}"  minor="${parts[2]}"
regex::groups() {
  local -r __rg_str="${1-}" __rg_pattern="${2-}"
  local -rn __rg_ref="${3:?output array name required}"
  __rg_ref=()
  [[ "${__rg_str}" =~ ${__rg_pattern} ]] || return 1
  local -i __rg_i
  for (( __rg_i = 1; __rg_i < ${#BASH_REMATCH[@]}; __rg_i++ )); do
    __rg_ref+=("${BASH_REMATCH[__rg_i]}")
  done
}

# @description One capture group of the FIRST match, printed
# @description Одна группа захвата ПЕРВОГО совпадения, вывод в stdout
#   (Python: re.search(...).group(n)). Group 0 = whole match.
# @param $1 String / Строка
# @param $2 Pattern (ERE) / Паттерн (ERE)
# @param $3 Group index, default 0 / Номер группы, по умолчанию 0
# @stdout the group, possibly empty / группа, возможно пустая
# @return 0 matched, 1 no match or group out of range
# @example
#   ext="$(regex::group "${file}" '\.([^.]+)$' 1)"
regex::group() {
  local -r __rg_str="${1-}" __rg_pattern="${2-}"
  local -r __rg_n="${3:-0}"
  [[ "${__rg_n}" =~ ^[0-9]+$ ]] || return 1
  [[ "${__rg_str}" =~ ${__rg_pattern} ]] || return 1
  if (( __rg_n < ${#BASH_REMATCH[@]} )); then
    printf '%s\n' "${BASH_REMATCH[__rg_n]}"
    return 0
  fi
  return 1
}

# @description Replace all occurrences with backref support (Python: re.sub).
# @description Заменить все вхождения с поддержкой обратных ссылок
#   (Python: re.sub). GNU sed -zE: whole string is one line, \1..\9 and &
#   work in the replacement. Linux-only (GNU sed).
# @param $1 String / Строка
# @param $2 Pattern (ERE) / Паттерн (ERE)
# @param $3 Replacement, may use \1, & / Замена, может использовать \1, &
# @stdout the replaced string / заменённая строка
# @example
#   csv="$(regex::replace "${csv}" ';' ',')"
#   snake="$(regex::replace "${name}" '([a-z])([A-Z])' '\1_\2')"
regex::replace() {
  local -r __rg_str="${1-}" __rg_pattern="${2-}" __rg_repl="${3-}"
  local __rg_pat __rg_repl_esc
  __rg_pat="${__rg_pattern//\//\\/}"
  __rg_pat="${__rg_pat//$'\n'/\\n}"
  __rg_repl_esc="${__rg_repl//\//\\/}"
  __rg_repl_esc="${__rg_repl_esc//$'\n'/\\n}"
  printf '%s' "${__rg_str}" | sed -zE "s/${__rg_pat}/${__rg_repl_esc}/g"
}

# @description Split a string on a regex (Python: re.split).
# @description Разбить строку по регулярке (Python: re.split).
# @param $1 String / Строка
# @param $2 Pattern (ERE, awk) / Паттерн (ERE, awk)
# @param $3 Output array name (will be reset) / Имя выходного массива
# @example
#   regex::split "a,1;b,2" '[,;]' cells
regex::split() {
  local -rn __rg_ref="${3:?output array name required}"
  local -r __rg_str="${1-}" __rg_pattern="${2-}"
  __rg_ref=()
  is::empty "${__rg_str}" && return 0
  local -a __rg_tmp=()
  mapfile -t __rg_tmp < <(awk -v pat="${__rg_pattern}" \
    '{ n = split($0, a, pat); for (i = 1; i <= n; i++) print a[i] }' <<< "${__rg_str}")
  __rg_ref=("${__rg_tmp[@]}")
}