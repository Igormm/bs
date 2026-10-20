#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, подстановки параметров, tr; без ${x^^}, ${x//a/b}, [[ ]] и printf -v / valid POSIX sh: case, parameter expansion, tr; no ${x^^}, ${x//a/b}, [[ ]] or printf -v
# @tier core — builtins and tr; works everywhere
#
# core/str.sh — строки для всех оболочек: регистр, обрезка, замена, проверки, склейка
# core/str.sh — strings for every shell: case, trimming, replacing, checks, joining
#
# ЗАЧЕМ / WHY
#   Одни и те же приёмы были разбросаны по ядру: bs_log_replace_all (core/logger.sh), tr для
#   верхнего регистра (core/prereq.sh, core/errorhandler.sh), цикл разбора по символам
#   (core/utils.sh). Здесь они собраны; результат — в stdout, одной строкой с переводом строки.
#   The same tricks were scattered over the kernel: bs_log_replace_all (core/logger.sh), tr for
#   upper case (core/prereq.sh, core/errorhandler.sh), the per-character loop (core/utils.sh).
#   They are collected here; the result goes to stdout as one line with a newline.
#
# ИМЕНА / NAMES
#   bs_str_upper, lower, trim, ltrim, rtrim, replace, contains, starts_with, ends_with, repeat,
#   join, before, after, width, head. Имена str::upper … str::repeat принадлежат core/lang.sh (bash, шаблон
#   замены — glob) и остаются как есть: псевдонимы здесь НЕ создаются, чтобы не подменить их.
#   bs_str_* — POSIX-версии с теми же именами; отличия: bs_str_replace заменяет ДОСЛОВНУЮ
#   подстроку, а не glob; trim срезает пробел, табуляцию, CR и LF.
#   The names str::upper … str::repeat belong to core/lang.sh (bash; the replace pattern is a
#   glob) and stay as they are: NO aliases are made here, so they are not overridden. bs_str_*
#   are POSIX versions with the same names; differences: bs_str_replace replaces a LITERAL
#   substring, not a glob; trim cuts space, tab, CR and LF.
#
# ДЛИНА / LENGTH
#   Длину считает bs_str_width — в символах UTF-8, одинаково во всех оболочках (байты минус байты
#   продолжения 0x80–0xBF). Голое ${#s} зависит от оболочки и локали: dash и mksh считают байты,
#   bash, zsh и ksh — символы по локали. Дополнение до ширины (pad) строится на bs_str_width.
#   The length is counted by bs_str_width — in UTF-8 characters, the same in every shell (bytes minus
#   the continuation bytes 0x80–0xBF). A bare ${#s} depends on the shell and the locale: dash and
#   mksh count bytes, bash, zsh and ksh count characters by locale. Padding to a width builds on
#   bs_str_width.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard STR || return 0

# @description В верхний регистр (ASCII и локаль tr) / To upper case
# @param $1 string / строка
# @stdout the string / строка
bs_str_upper() {
  printf '%s\n' "${1-}" | tr '[:lower:]' '[:upper:]'
}

# @description В нижний регистр / To lower case
# @param $1 string / строка
# @stdout the string / строка
bs_str_lower() {
  printf '%s\n' "${1-}" | tr '[:upper:]' '[:lower:]'
}

# @description Срезать пробельные символы слева (пробел, табуляция, CR, LF) / Cut whitespace on the left (space, tab, CR, LF)
# @param $1 string / строка
# @stdout the string / строка
bs_str_ltrim() {
  __bs_str_s=${1-}
  # CR берём из printf: литерал возврата каретки в case не вставить переносимо. Если printf недоступен
  # (в mksh он внешний), CR пуст — тогда он не учитывается: пустой шаблон "$cr"* совпал бы со всем.
  # CR comes from printf: a literal carriage return cannot be put in a case portably. If printf is
  # unavailable (it is external in mksh), CR is empty and is skipped: the empty pattern "$cr"* would match anything.
  __bs_str_cr=$(printf '\r' 2>/dev/null) || __bs_str_cr=''
  while [ -n "$__bs_str_s" ]; do
    case "$__bs_str_s" in
      ' '*|'	'*|'
'*) __bs_str_s=${__bs_str_s#?} ;;
      *)
        if [ -n "$__bs_str_cr" ]; then
          case "$__bs_str_s" in
            "$__bs_str_cr"*) __bs_str_s=${__bs_str_s#?}; continue ;;
          esac
        fi
        break ;;
    esac
  done
  printf '%s\n' "$__bs_str_s"
}

# @description Срезать пробельные символы справа / Cut whitespace on the right
# @param $1 string / строка
# @stdout the string / строка
bs_str_rtrim() {
  __bs_str_s=${1-}
  __bs_str_cr=$(printf '\r' 2>/dev/null) || __bs_str_cr=''
  while [ -n "$__bs_str_s" ]; do
    case "$__bs_str_s" in
      *' '|*'	'|*'
') __bs_str_s=${__bs_str_s%?} ;;
      *)
        if [ -n "$__bs_str_cr" ]; then
          case "$__bs_str_s" in
            *"$__bs_str_cr") __bs_str_s=${__bs_str_s%?}; continue ;;
          esac
        fi
        break ;;
    esac
  done
  printf '%s\n' "$__bs_str_s"
}

# @description Срезать пробельные символы с обоих краёв / Cut whitespace on both sides
# @param $1 string / строка
# @stdout the string / строка
bs_str_trim() {
  __bs_str_t=$(bs_str_ltrim "${1-}")
  bs_str_rtrim "$__bs_str_t"
}

# @description Заменить все вхождения ДОСЛОВНОЙ подстроки (не glob) / Replace every occurrence of a LITERAL substring (not a glob)
# @param $1 string / строка
# @param $2 substring to find; empty leaves the string as it is / что искать; пусто — строка без изменений
# @param $3 replacement / чем заменить
# @stdout the string / строка
bs_str_replace() {
  __bs_str_rs=${1-}
  __bs_str_from=${2-}
  __bs_str_to=${3-}
  __bs_str_ro=''
  if [ -z "$__bs_str_from" ]; then
    printf '%s\n' "$__bs_str_rs"
    return 0
  fi
  while :; do
    case "$__bs_str_rs" in
      *"$__bs_str_from"*)
        __bs_str_ro="${__bs_str_ro}${__bs_str_rs%%"$__bs_str_from"*}${__bs_str_to}"
        __bs_str_rs=${__bs_str_rs#*"$__bs_str_from"} ;;
      *)
        __bs_str_ro="${__bs_str_ro}${__bs_str_rs}"
        break ;;
    esac
  done
  printf '%s\n' "$__bs_str_ro"
}

# @description Содержит ли строка подстроку (статус) / Whether the string contains the substring (status)
# @param $1 string / строка
# @param $2 substring / подстрока
# @returns 0 contains / 1 not
bs_str_contains() {
  case "${1-}" in
    *"${2-}"*) return 0 ;;
  esac
  return 1
}

# @description Начинается ли строка с префикса (статус) / Whether the string starts with the prefix (status)
# @param $1 string / строка
# @param $2 prefix / префикс
# @returns 0 yes / 1 no
bs_str_starts_with() {
  case "${1-}" in
    "${2-}"*) return 0 ;;
  esac
  return 1
}

# @description Заканчивается ли строка суффиксом (статус) / Whether the string ends with the suffix (status)
# @param $1 string / строка
# @param $2 suffix / суффикс
# @returns 0 yes / 1 no
bs_str_ends_with() {
  case "${1-}" in
    *"${2-}") return 0 ;;
  esac
  return 1
}

# @description Повторить строку N раз / Repeat a string N times
# @param $1 string / строка
# @param $2 count, an integer >= 0 / число повторов, целое >= 0
# @stdout the string / строка
# @returns 0 ok / 1 count is not a non-negative integer
bs_str_repeat() {
  __bs_str_rp=${1-}
  __bs_str_rn=${2-}
  case "$__bs_str_rn" in
    ''|*[!0-9]*) return 1 ;;
  esac
  # ведущие нули: $(( 08 )) — ошибка восьмеричного числа в dash и bash / leading zeros: $(( 08 )) is an octal error in dash and bash
  while :; do
    case "$__bs_str_rn" in 0?*) __bs_str_rn=${__bs_str_rn#0} ;; *) break ;; esac
  done
  __bs_str_ro=''
  while [ "$__bs_str_rn" -gt 0 ]; do
    __bs_str_ro="${__bs_str_ro}${__bs_str_rp}"
    __bs_str_rn=$((__bs_str_rn - 1))
  done
  printf '%s\n' "$__bs_str_ro"
}

# @description Склеить аргументы разделителем независимо от IFS / Join the arguments with a separator whatever IFS is
# @param $1 separator (may be empty) / разделитель (может быть пустым)
# @param $@ strings / строки
# @stdout the string / строка
bs_str_join() {
  __bs_str_sep=${1-}
  if [ $# -gt 0 ]; then shift; fi
  __bs_str_ro=''
  __bs_str_first=1
  for __bs_str_w in "$@"; do
    if [ "$__bs_str_first" = 1 ]; then
      __bs_str_ro=$__bs_str_w
      __bs_str_first=0
    else
      __bs_str_ro="${__bs_str_ro}${__bs_str_sep}${__bs_str_w}"
    fi
  done
  printf '%s\n' "$__bs_str_ro"
}

# @description Часть строки до первого вхождения разделителя (вся строка, если его нет) / The part before the first separator (the whole string if there is none)
# @param $1 string / строка
# @param $2 separator (literal, non-empty) / разделитель (дословный, непустой)
# @stdout the string / строка
# @returns 0 ok / 1 empty separator
bs_str_before() {
  [ -n "${2-}" ] || return 1
  __bs_str_s=${1-}
  printf '%s\n' "${__bs_str_s%%"${2}"*}"
}

# @description Часть строки после первого вхождения разделителя (пусто, если его нет) / The part after the first separator (empty if there is none)
# @param $1 string / строка
# @param $2 separator (literal, non-empty) / разделитель (дословный, непустой)
# @stdout the string / строка
# @returns 0 ok / 1 empty separator or no separator in the string
bs_str_after() {
  [ -n "${2-}" ] || return 1
  __bs_str_s=${1-}
  case "$__bs_str_s" in
    *"$2"*) printf '%s\n' "${__bs_str_s#*"${2}"}" ;;
    *) return 1 ;;
  esac
}

# @description Ширина строки в символах UTF-8: байты минус байты продолжения (0x80–0xBF); одинаково во всех оболочках / The width of a string in UTF-8 characters: bytes minus the continuation bytes (0x80–0xBF); the same in every shell
# @param $1 string / строка
# @stdout number of characters / число символов
bs_str_width() {
  __bs_str_wn=$(printf '%s' "${1-}" | LC_ALL=C tr -d '\200-\277' | wc -c)
  printf '%s\n' "$((__bs_str_wn))"
}

# @description Первые N символов UTF-8 (вся строка, если она короче) / The first N UTF-8 characters (the whole string if it is shorter)
# @param $1 string / строка
# @param $2 count, an integer >= 0 / число символов, целое >= 0
# @stdout the prefix / начало строки
# @returns 0 ok / 1 count is not a non-negative integer
bs_str_head() {
  case "${2-}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  # Подоболочка с LC_ALL=C: ${s#?} снимает один БАЙТ в любой оболочке / A subshell with LC_ALL=C: ${s#?} takes off one BYTE in every shell
  (
    LC_ALL=C
    export LC_ALL
    __bs_str_hs=${1-}
    __bs_str_hn=$(($2))
    __bs_str_ho=''
    __bs_str_hc=0
    while [ "$__bs_str_hc" -lt "$__bs_str_hn" ] && [ -n "$__bs_str_hs" ]; do
      __bs_str_hb=${__bs_str_hs%"${__bs_str_hs#?}"}
      __bs_str_hs=${__bs_str_hs#?}
      __bs_str_ho="${__bs_str_ho}${__bs_str_hb}"
      # байты продолжения тянутся за ведущим байтом; ASCII проверять форком незачем / continuation bytes follow the lead byte; an ASCII byte needs no fork
      while [ -n "$__bs_str_hs" ]; do
        __bs_str_hb=${__bs_str_hs%"${__bs_str_hs#?}"}
        case "$__bs_str_hb" in
          ' '|[\!-~]) break ;;
        esac
        if [ -z "$(printf '%s' "$__bs_str_hb" | tr -d '\200-\277')" ]; then
          __bs_str_ho="${__bs_str_ho}${__bs_str_hb}"
          __bs_str_hs=${__bs_str_hs#?}
        else
          break
        fi
      done
      __bs_str_hc=$((__bs_str_hc + 1))
    done
    printf '%s\n' "$__bs_str_ho"
  )
}
