#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, подстановки параметров, awk; без $(( )) для больших чисел (в mksh она 32-битная) / valid POSIX sh: case, parameter expansion, awk; no $(( )) for big numbers (it is 32-bit in mksh)
# @tier core — builtins and awk; works everywhere
#
# core/num.sh — целые числа для всех оболочек: проверка, нормализация, арифметика без переполнения
# core/num.sh — integers for every shell: checks, normalising, arithmetic without overflow
#
# ЗАЧЕМ / WHY
#   $(( )) в mksh 32-битная: 3*1073741824 даёт -1073741824 (так переполнялись 3 GiB в
#   core/fmt.sh), а «08» в $(( )) — ошибка восьмеричного числа в dash и bash и число 8 в mksh
#   (так лечили bs_error_retry). Проверку «только цифры» повторяли errorhandler и fmt.
#   Здесь арифметика идёт через awk (точное целое до 15 цифр), а ввод проверяется и
#   нормализуется одним способом.
#   $(( )) is 32-bit in mksh: 3*1073741824 gives -1073741824 (this is how 3 GiB overflowed in
#   core/fmt.sh), and "08" in $(( )) is an octal error in dash and bash but 8 in mksh (what
#   bs_error_retry worked around). The "digits only" check was repeated in errorhandler and fmt.
#   Here the arithmetic runs in awk (an exact integer up to 15 digits) and the input is checked
#   and normalised in one way.
#
# ПРЕДЕЛЫ / LIMITS
#   Целые от -999999999999999 до 999999999999999 (15 цифр). Вход вне предела или результат за
#   пределом — статус 1: молча неточный ответ хуже отказа.
#   Integers from -999999999999999 to 999999999999999 (15 digits). An input or a result outside
#   the limit is status 1: a silently inexact answer is worse than a refusal.
#
# СТАТУСЫ / STATUS
#   0 — успех, 1 — не целое число или предел, 2 — деление на ноль.
#   0 is success, 1 is "not an integer" or the limit, 2 is a division by zero.
#
# ИМЕНА / NAMES
#   Real functions: bs_num_is_uint, bs_num_is_int, bs_num_dec, bs_num_add, bs_num_sub,
#   bs_num_mul, bs_num_div, bs_num_mod, bs_num_cmp. New API: no old `::` names, so no aliases.
#   Настоящие функции: bs_num_*. Новый API: прежних имён с `::` нет, псевдонимов нет.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard NUM || return 0

# @description Строка из одних цифр (статус) / The string is digits only (status)
# @param $1 string / строка
# @returns 0 yes / 1 no (an empty string is not a number)
bs_num_is_uint() {
  case "${1-}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  return 0
}

# @description Целое с необязательным минусом (статус) / An integer with an optional minus (status)
# @param $1 string / строка
# @returns 0 yes / 1 no
bs_num_is_int() {
  case "${1-}" in
    -*) bs_num_is_uint "${1#-}" ;;
    *) bs_num_is_uint "${1-}" ;;
  esac
}

# @description Привести целое к десятичному виду без ведущих нулей: 007 → 7, -0 → 0 / Normalise an integer to decimal without leading zeros: 007 → 7, -0 → 0
# @param $1 integer / целое
# @stdout the number / число
# @returns 0 ok / 1 not an integer or beyond 15 digits
bs_num_dec() {
  __bs_num_s=${1-}
  __bs_num_neg=''
  case "$__bs_num_s" in
    -*) __bs_num_neg='-'; __bs_num_s=${__bs_num_s#-} ;;
  esac
  bs_num_is_uint "$__bs_num_s" || return 1
  while :; do
    case "$__bs_num_s" in 0?*) __bs_num_s=${__bs_num_s#0} ;; *) break ;; esac
  done
  if [ "${#__bs_num_s}" -gt 15 ]; then return 1; fi
  if [ "$__bs_num_s" = 0 ]; then __bs_num_neg=''; fi
  printf '%s%s\n' "$__bs_num_neg" "$__bs_num_s"
}

# @private
# @description Выполнить действие над двумя целыми в awk; результат в stdout / Run an operation on two integers in awk; the result is on stdout
# @param $1 operation: + - * / % c / действие
# @param $2 first integer / первое целое
# @param $3 second integer / второе целое
bs_num_op() {
  __bs_num_a=$(bs_num_dec "${2-}") || return 1
  __bs_num_b=$(bs_num_dec "${3-}") || return 1
  awk -v op="$1" -v a="$__bs_num_a" -v b="$__bs_num_b" 'BEGIN {
      if (op == "+") r = a + b
      else if (op == "-") r = a - b
      else if (op == "*") r = a * b
      else if (op == "c") { print (a < b ? -1 : (a > b ? 1 : 0)); exit 0 }
      else {
        if (b == 0) exit 2
        q = a / b
        q = (q < 0 ? -int(-q) : int(q))
        r = (op == "/") ? q : a - b * q
      }
      if (r >= 1e15 || r <= -1e15) exit 1
      if (r == 0) print "0"; else printf "%.0f\n", r
    }'
}

# @description Сумма / Sum
# @param $1 integer / целое
# @param $2 integer / целое
# @stdout the result / результат
bs_num_add() {
  bs_num_op + "${1-}" "${2-}"
}

# @description Разность $1 - $2 / Difference $1 - $2
# @param $1 integer / целое
# @param $2 integer / целое
# @stdout the result / результат
bs_num_sub() {
  bs_num_op - "${1-}" "${2-}"
}

# @description Произведение (результат тоже в пределах 15 цифр) / Product (the result is also within 15 digits)
# @param $1 integer / целое
# @param $2 integer / целое
# @stdout the result / результат
bs_num_mul() {
  bs_num_op '*' "${1-}" "${2-}"
}

# @description Целое частное с отбрасыванием к нулю (как $(( ))) / Integer quotient truncated toward zero (like $(( )))
# @param $1 dividend / делимое
# @param $2 divisor / делитель
# @stdout the result / результат
# @returns 0 ok / 1 not integers or limit / 2 division by zero
bs_num_div() {
  bs_num_op / "${1-}" "${2-}"
}

# @description Остаток с знаком делимого (как $(( ))) / Remainder with the sign of the dividend (like $(( )))
# @param $1 dividend / делимое
# @param $2 divisor / делитель
# @stdout the result / результат
# @returns 0 ok / 1 not integers or limit / 2 division by zero
bs_num_mod() {
  bs_num_op % "${1-}" "${2-}"
}

# @description Сравнить два целых: -1, 0 или 1 / Compare two integers: -1, 0 or 1
# @param $1 integer / целое
# @param $2 integer / целое
# @stdout -1 when $1 < $2, 0 when equal, 1 when $1 > $2 / -1, 0 или 1
bs_num_cmp() {
  bs_num_op c "${1-}" "${2-}"
}
