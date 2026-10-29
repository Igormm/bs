#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, printf, пробные запуски grep/sed/awk / valid POSIX sh: case, printf, probe runs of grep/sed/awk
# @tier core — grep/sed/awk; works everywhere (GNU, busybox, BSD)
#
# core/regex.sh — работа с регулярными выражениями (POSIX ERE) / regex helpers (POSIX ERE)
#
# Это POSIX-ярус регулярных выражений: те же операции, что lib/data/regex.sh
# (bash4), но без bash-конструкций и с fallback для busybox (где grep -o /
# sed -E могут отсутствовать). Движки: grep -E, sed -E, awk — с пробой и кэшем
# на сессию.
# This is the POSIX tier of regexes: the same operations as lib/data/regex.sh
# (bash4) but without bash constructs and with busybox fallbacks (where grep -o
# / sed -E may be missing). Engines: grep -E, sed -E, awk — probed and cached.
#
# Диалект / Dialect: POSIX ERE. Нет \d, \s, lookaround — это PCRE/расширения.
# Для PCRE используй lib/data/regex.sh (regex::*, bash4). / No \d, \s, lookaround
# — those are PCRE extensions. For PCRE use lib/data/regex.sh (regex::*, bash4).
#
# ИМЕНА / NAMES
#   Real functions: bs_re_probe, bs_re_match, bs_re_fullmatch, bs_re_find,
#   bs_re_count, bs_re_replace, bs_re_split. Новый API: прежних имён с `::` нет.
#   Real functions: bs_re_probe, bs_re_match, bs_re_fullmatch, bs_re_find,
#   bs_re_count, bs_re_replace, bs_re_split. New API: no old `::` names.

# Source Guard / Защита от повторной загрузки
bs_guard CORE_REGEX || return 0

# Кэш проб: 0/1. Имена __bs_re_* зарезервированы за этим файлом.
# Probe cache: 0/1. The __bs_re_* names belong to this file.
__bs_re_probed=0
__bs_re_grep_o=0
__bs_re_sed_e=0
__bs_re_awk=0

# @description Проба возможностей движков, кэш на сессию / Probe the engines once, cache it
# @sets __bs_re_grep_o, __bs_re_sed_e, __bs_re_awk
bs_re_probe() {
  [ "${__bs_re_probed}" = 1 ] && return 0
  if printf 'ab' | grep -o 'a' >/dev/null 2>&1; then __bs_re_grep_o=1; fi
  if printf 'a' | sed -E 's/a/b/' >/dev/null 2>&1; then __bs_re_sed_e=1; fi
  if command -v awk >/dev/null 2>&1; then __bs_re_awk=1; fi
  __bs_re_probed=1
  return 0
}

# @description Предикат: строка содержит вхождение ERE (re.search) / Predicate: the
#   string contains an ERE match (re.search)
# @param $1 строка / string
# @param $2 ERE-паттерн / ERE pattern
# @returns 0 есть / match, 1 нет / no match, 2 плохой паттерн / bad pattern
bs_re_match() {
  printf '%s\n' "${1-}" | grep -Eq -e "${2-}"
}

# @description Предикат: строка ЦЕЛИКОМ соответствует ERE (re.fullmatch) / Predicate:
#   the string fully matches the ERE (re.fullmatch)
# @param $1 строка / string
# @param $2 ERE-паттерн (без якорей) / ERE pattern (un-anchored)
# @returns 0/1/2 как у bs_re_match / as bs_re_match
bs_re_fullmatch() {
  bs_re_match "${1-}" "^(${2-})\$"
}

# @description Первое вхождение ERE (grep -oE; fallback awk) / First ERE match
# @param $1 строка / string
# @param $2 ERE-паттерн / ERE pattern
# @stdout первое совпадение / the first match
# @returns 0 найдено / found, 1 нет / none
bs_re_find() {
  bs_re_probe
  if [ "${__bs_re_grep_o}" = 1 ]; then
    printf '%s\n' "${1-}" | grep -oE -e "${2-}" | sed -n '1p'
  elif [ "${__bs_re_awk}" = 1 ]; then
    # fallback: awk match() по первой строке; \ в паттерне не обрабатывается
    # fallback: awk match() on the first line; \ in the pattern is not processed
    printf '%s\n' "${1-}" | awk -v pat="${2-}" 'match($0, pat) { print substr($0, RSTART, RLENGTH); exit }'
  else
    printf '%s\n' "bs_re_find: grep -o and awk unavailable" >&2
    return 1
  fi
}

# @description Число вхождений ERE / Number of ERE matches
# @param $1 строка / string
# @param $2 ERE-паттерн / ERE pattern
# @stdout число / the count
bs_re_count() {
  bs_re_probe
  if [ "${__bs_re_grep_o}" = 1 ]; then
    printf '%s\n' "${1-}" | grep -oE -e "${2-}" | wc -l | tr -d ' '
  elif [ "${__bs_re_awk}" = 1 ]; then
    printf '%s\n' "${1-}" | awk -v pat="${2-}" '{ n=0; s=$0; while (match(s, pat)) { n++; s=substr(s, RSTART+RLENGTH) } print n }'
  else
    printf '0\n'
  fi
}

# @description Заменить ВСЕ вхождения ERE (sed -E) / Replace ALL ERE matches (sed -E)
# @param $1 строка / string
# @param $2 ERE-паттерн / ERE pattern
# @param $3 замена (sed-синтаксис, & — совпадение) / replacement (sed syntax, & — the match)
# @stdout строка после замены / the replaced string
bs_re_replace() {
  bs_re_probe
  if [ "${__bs_re_sed_e}" = 1 ]; then
    printf '%s\n' "${1-}" | sed -E "s/${2-}/${3-}/g"
  else
    # POSIX BRE без -E: \( \) — группировка / POSIX BRE without -E: \( \) group
    printf '%s\n' "${1-}" | sed "s/${2-}/${3-}/g"
  fi
}

# @description Разбить строку по ERE (awk) / Split a string on an ERE (awk)
# @param $1 строка / string
# @param $2 ERE-разделитель / ERE separator
# @stdout поля по одному в строке / the fields, one per line
bs_re_split() {
  bs_re_probe
  if [ "${__bs_re_awk}" = 1 ]; then
    printf '%s\n' "${1-}" | awk -v pat="${2-}" '{ n=split($0, a, pat); for (i=1; i<=n; i++) print a[i] }'
  else
    printf '%s\n' "${1-}"
  fi
}
