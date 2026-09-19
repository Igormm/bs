#!/usr/bin/env bs
# shellcheck shell=bash
# lib/data/regex.sh — регулярные выражения (ERE + PCRE) / regex module

# @depends core/lang, core/utils, core/errorhandler
# @tier core

# Source Guard
bs::guard "LIB_DATA_REGEX" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh" "../../core/utils.sh" "../../core/errorhandler.sh"

# ==========================================
# Regular expressions / Регулярные выражения
#
# Engines, chosen by the function / Движки по выбору функции:
#   [[ =~ ]]       — POSIX ERE, zero forks, capture groups (regex::groups)
#   grep -E / -o   — ERE, all matches, line-based
#   grep -P        — PCRE: lookahead/lookbehind, \d, \w, lazy quantifiers,
#                    backrefs (GNU grep, Linux)
#   perl           — PCRE-like fallback when grep -P is missing (BSD/macOS)
#   sed -zE        — multiline replace: whole string is one line (GNU sed)
#   perl -0        — multiline replace fallback (slurp mode)
#   pure bash      — last-resort line-based replace (no -z semantics)
# Probe chains, cached once per session (portability.md §4) /
# Цепочки проб, кэш на сессию (portability.md §4):
#   PCRE:          grep -P → perl → error "PCRE unavailable" (101)
#   multiline sed: sed -z → perl -0 → pure bash (построчно, ограниченно)
# Engine selection / Выбор движка:
#   regex::matches/find/count accept a trailing `--pcre` flag; without it
#   they use ERE, which works on any grep. regex::groups uses POSIX ERE
#   (bash =~). regex::replace uses the multiline chain above.
#   regex::matches/find/count принимают флаг `--pcre` в конце; без него —
#   ERE, работающий с любым grep. regex::groups — POSIX ERE (bash =~).
#   regex::replace — многострочная цепочка выше.
# ==========================================

# Cached capability probes (probed once, reused on every call) /
# Кэш проб возможностей (проба один раз, переиспользуется в каждом вызове)
# RX_PCRE: 1 = grep -P works, 0 = not, "" = not probed yet
# RX_PCRE: 1 = grep -P работает, 0 = нет, "" = ещё не проверялось
declare -g RX_PCRE=""
# RX_SED_Z: 1 = sed -z works, 0 = not, "" = not probed yet
# RX_SED_Z: 1 = sed -z работает, 0 = нет, "" = ещё не проверялось
declare -g RX_SED_Z=""

# @private
# @description Probe grep -P once, cache in RX_PCRE / Проба grep -P один раз.
regex::__probe_pcre() {
  if is::command grep && printf 'x' | grep -Pq 'x' 2>/dev/null; then
    RX_PCRE=1
  else
    RX_PCRE=0
  fi
}

# @private
# @description Probe sed -z once, cache in RX_SED_Z / Проба sed -z один раз.
regex::__probe_sed_z() {
  if is::command sed && printf 'a\nb' | sed -z 's/a/X/' >/dev/null 2>&1; then
    RX_SED_Z=1
  else
    RX_SED_Z=0
  fi
}

# @description Predicate: string matches the pattern (Python: re.search).
# @description Предикат: строка соответствует паттерну (Python: re.search).
# @param $1 String / Строка
# @param $2 Pattern (ERE; PCRE with --pcre) / Паттерн (ERE; PCRE с --pcre)
# @param $3 [optional] --pcre / флаг PCRE
# @return 0 matches, 1 no match, 2 invalid pattern (ERE mode),
#         101 PCRE unavailable (no grep -P, no perl)
# @return 0 совпадение, 1 нет совпадения, 2 неверный паттерн (ERE),
#         101 PCRE недоступен (нет grep -P и нет perl)
# @example
#   if regex::matches "${url}" '^https?://' ; then ...
#   if regex::matches "$line" '\d{4}-\d{2}-\d{2}' --pcre; then ...
regex::matches() {
  local -r __rg_str="${1-}" __rg_pattern="${2-}"
  if [[ "${3-}" == "--pcre" ]]; then
    is::command grep || return 1
    is::empty "${RX_PCRE}" && regex::__probe_pcre
    if (( RX_PCRE == 1 )); then
      grep -Pq -- "${__rg_pattern}" <<< "${__rg_str}"
      return $?
    fi
    if is::command perl; then
      # perl as PCRE-like fallback / perl как PCRE-подобный фолбэк
      # shellcheck disable=SC2016
      RX_PERL_PAT="${__rg_pattern}" perl -ne '$f = 1, last if /$ENV{RX_PERL_PAT}/; END { exit !$f }' <<< "${__rg_str}"
      return $?
    fi
    log::error "regex::matches: PCRE unavailable (grep -P and perl not found) / PCRE недоступен (нет grep -P и perl)"
    return "${LIB_ERROR_DEPENDENCY_MISSING:-101}"
  fi
  local __rg_status=0 __rg_err=""
  __rg_err="$({ [[ "${__rg_str}" =~ ${__rg_pattern} ]]; } 2>&1)" || __rg_status=$?
  if (( __rg_status == 2 )); then
    log::error "regex::matches: invalid ERE pattern: ${__rg_pattern} (bash: ${__rg_err}) / неверный ERE-паттерн: ${__rg_pattern} (bash: ${__rg_err})"
    return 2
  fi
  return "${__rg_status}"
}

# @description Predicate alias of regex::matches / Предикат-алиас matches.
regex::test() {
  regex::matches "$@"
}

# @description All matches as lines (Python: re.findall).
# @description Все совпадения построчно (Python: re.findall).
#   Line-based: a match cannot span newlines (grep semantics). --pcre for
#   PCRE (grep -P, or perl when grep -P is missing). Empty OUT prints matches
#   to stdout.
#   Построчно: совпадение не может пересекать переводы строк (семантика
#   grep). --pcre для PCRE (grep -P, или perl, если grep -P отсутствует).
#   Пустой OUT печатает совпадения в stdout.
# @param $1 String / Строка
# @param $2 Pattern / Паттерн
# @param $3 [optional] Output array name (will be reset) / Имя выходного массива
# @param $4 [optional] --pcre / флаг PCRE
# @return 0 ok (even with zero matches), 1 grep unavailable,
#         101 PCRE unavailable (no grep -P, no perl)
# @return 0 успех (даже при нуле совпадений), 1 нет grep,
#         101 PCRE недоступен (нет grep -P и нет perl)
# @example
#   regex::find "${log}" '\[ERROR\]' errors
regex::find() {
  local -r __rg_str="${1-}" __rg_pattern="${2-}"
  local -r __rg_out="${3-}" __rg_pcre="${4-}"
  local __rg_result=""
  if [[ "${__rg_pcre}" == "--pcre" ]]; then
    is::command grep || return 1
    is::empty "${RX_PCRE}" && regex::__probe_pcre
    if (( RX_PCRE == 1 )); then
      __rg_result="$(grep -Po -- "${__rg_pattern}" <<< "${__rg_str}" 2>/dev/null || :)"
    elif is::command perl; then
      # shellcheck disable=SC2016
      __rg_result="$(RX_PERL_PAT="${__rg_pattern}" perl -ne 'while (/$ENV{RX_PERL_PAT}/g) { print $&, "\n" }' <<< "${__rg_str}" 2>/dev/null || :)"
    else
      log::error "regex::find: PCRE unavailable (grep -P and perl not found) / PCRE недоступен (нет grep -P и perl)"
      return "${LIB_ERROR_DEPENDENCY_MISSING:-101}"
    fi
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
# @return 0 ok, 1 grep unavailable, 101 PCRE unavailable (no grep -P, no perl)
# @return 0 успех, 1 нет grep, 101 PCRE недоступен (нет grep -P и perl)
# @example
#   n="$(regex::count "${conf}" '^\s*\w+=')"
regex::count() {
  local -r __rg_str="${1-}" __rg_pattern="${2-}" __rg_pcre="${3-}"
  local __rg_n=""
  if [[ "${__rg_pcre}" == "--pcre" ]]; then
    is::command grep || return 1
    is::empty "${RX_PCRE}" && regex::__probe_pcre
    if (( RX_PCRE == 1 )); then
      __rg_n="$(grep -Po -- "${__rg_pattern}" <<< "${__rg_str}" 2>/dev/null | wc -l || true)"
    elif is::command perl; then
      # shellcheck disable=SC2016
      __rg_n="$(RX_PERL_PAT="${__rg_pattern}" perl -ne 'while (/$ENV{RX_PERL_PAT}/g) { print $&, "\n" }' <<< "${__rg_str}" 2>/dev/null | wc -l || true)"
    else
      log::error "regex::count: PCRE unavailable (grep -P and perl not found) / PCRE недоступен (нет grep -P и perl)"
      return "${LIB_ERROR_DEPENDENCY_MISSING:-101}"
    fi
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
#   (Python: re.sub). GNU sed -zE treats the whole string as one line, so
#   \1..\9 and & work in the replacement. Probe chain (cached in RX_SED_Z):
#   sed -z → perl -0 → pure bash (line-based: pattern/replacement cannot span
#   newlines). Engine failure returns a non-zero status — never a silent
#   empty result.
#   GNU sed -zE рассматривает всю строку как одну, поэтому \1..\9 и &
#   работают в замене. Цепочка проб (кэш в RX_SED_Z): sed -z → perl -0 →
#   чистый bash (построчно: паттерн/замена не пересекают переводы строк).
#   Сбой движка возвращает ненулевой статус — никогда не тихо пустой
#   результат.
# @param $1 String / Строка
# @param $2 Pattern (ERE) / Паттерн (ERE)
# @param $3 Replacement, may use \1, & / Замена, может использовать \1, &
# @stdout the replaced string / заменённая строка
# @return 0 ok; non-zero engine failure (sed/perl status)
# @return 0 успех; ненулевой — сбой движка (статус sed/perl)
# @example
#   csv="$(regex::replace "${csv}" ';' ',')"
#   snake="$(regex::replace "${name}" '([a-z])([A-Z])' '\1_\2')"
regex::replace() {
  local -r __rg_str="${1-}" __rg_pattern="${2-}" __rg_repl="${3-}"
  local __rg_pat __rg_repl_esc __rg_status
  is::empty "${RX_SED_Z}" && regex::__probe_sed_z
  if (( RX_SED_Z == 1 )); then
    __rg_pat="${__rg_pattern//\//\\/}"
    __rg_pat="${__rg_pat//$'\n'/\\n}"
    __rg_repl_esc="${__rg_repl//\//\\/}"
    __rg_repl_esc="${__rg_repl_esc//$'\n'/\\n}"
    if ! printf '%s' "${__rg_str}" | sed -zE "s/${__rg_pat}/${__rg_repl_esc}/g"; then
      __rg_status="${PIPESTATUS[1]}"
      return "${__rg_status}"
    fi
    return 0
  fi
  if is::command perl; then
    __rg_pat="${__rg_pattern//\//\\/}"
    __rg_pat="${__rg_pat//$'\n'/\\n}"
    __rg_repl_esc="${__rg_repl//\//\\/}"
    __rg_repl_esc="${__rg_repl_esc//$'\n'/\\n}"
    if ! printf '%s' "${__rg_str}" | perl -0pe "s/${__rg_pat}/${__rg_repl_esc}/g"; then
      __rg_status="${PIPESTATUS[1]}"
      return "${__rg_status}"
    fi
    return 0
  fi
  regex::__replace_bash "${__rg_str}" "${__rg_pattern}" "${__rg_repl}"
}

# @private
# @description Last-resort line-based replace (no -z semantics: pattern and
#   replacement cannot span newlines; empty-match insertion differs from sed).
# @description Замена построчно в крайнем случае (без семантики -z: паттерн
#   и замена не пересекают переводы строк; вставка пустого совпадения
#   отличается от sed).
# @param $1 String / Строка
# @param $2 Pattern (ERE) / Паттерн (ERE)
# @param $3 Replacement, may use & and \1..\9 / Замена, может использовать & и \1..\9
# @stdout replaced string / заменённая строка
regex::__replace_bash() {
  local -r __rg_str="${1}" __rg_pattern="${2}" __rg_repl="${3}"
  local __rg_line __rg_out="" __rg_subst __rg_remain
  local __rg_match __rg_head __rg_tail __rg_exp __rg_first=1
  while IFS= read -r __rg_line || [[ -n "${__rg_line}" ]]; do
    __rg_subst=""
    __rg_remain="${__rg_line}"
    while [[ "${__rg_remain}" =~ ${__rg_pattern} ]]; do
      __rg_match="${BASH_REMATCH[0]}"
      __rg_head="${__rg_remain%%"${__rg_match}"*}"
      __rg_tail="${__rg_remain#*"${__rg_match}"}"
      __rg_exp="$(regex::__expand_repl "${__rg_repl}")"
      __rg_subst+="${__rg_head}${__rg_exp}"
      if is::empty "${__rg_match}"; then
        # пустое совпадение: продвинуться на 1 символ, чтобы не зациклиться
        # empty match: advance 1 char to avoid an infinite loop
        is::empty "${__rg_tail}" && break
        __rg_remain="${__rg_tail:1}"
      else
        __rg_remain="${__rg_tail}"
      fi
    done
    if (( __rg_first == 1 )); then
      __rg_first=0
      __rg_out="${__rg_subst}${__rg_remain}"
    else
      __rg_out+=$'\n'"${__rg_subst}${__rg_remain}"
    fi
  done <<< "${__rg_str}"
  printf '%s' "${__rg_out}"
}

# @private
# @description Expand a replacement string: & = whole match, \N = group N,
#   using the current BASH_REMATCH / Раскрыть строку замены: & = всё
#   совпадение, \N = группа N (из текущего BASH_REMATCH).
# @param $1 Replacement / Замена
# @stdout expanded replacement / раскрытая замена
regex::__expand_repl() {
  local -r __rg_repl="${1}"
  local __rg_out="" __rg_ch __rg_i
  for (( __rg_i = 0; __rg_i < ${#__rg_repl}; __rg_i++ )); do
    __rg_ch="${__rg_repl:__rg_i:1}"
    if [[ "${__rg_ch}" == "\\" && $(( __rg_i + 1 )) -lt ${#__rg_repl} ]]; then
      __rg_ch="${__rg_repl:$(( __rg_i + 1 )):1}"
      case "${__rg_ch}" in
        [1-9])
          __rg_out+="${BASH_REMATCH[${__rg_ch}]:-}"
          ;;
        *)
          __rg_out+="\\${__rg_ch}"
          ;;
      esac
      (( __rg_i++ ))
    elif [[ "${__rg_ch}" == "&" ]]; then
      __rg_out+="${BASH_REMATCH[0]:-}"
    else
      __rg_out+="${__rg_ch}"
    fi
  done
  printf '%s' "${__rg_out}"
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