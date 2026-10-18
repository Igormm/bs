#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, подстановки параметров, date, awk, head; без $(( )) для больших чисел (в mksh она 32-битная) / valid POSIX sh: case, parameter expansion, date, awk, head; no $(( )) for big numbers (it is 32-bit in mksh)
# @tier core — date, awk, head; works everywhere
#
# core/fmt.sh — форматирование размеров и метки времени
# core/fmt.sh — size formatting and timestamps
#
# ИМЕНА / NAMES
#   Real functions: bs_utils_human_size, bs_utils_head_bytes, bs_utils_now_s, bs_utils_now_ms, bs_utils_now_float,
#   bs_utils_stamp, bs_utils_log_stamp; in bash and zsh also utils::human_size, utils::head_bytes,
#   utils::now_s, utils::now_ms, utils::now_float, utils::stamp, utils::log_stamp (the old names).
#   Настоящие функции: bs_utils_human_size, bs_utils_head_bytes, bs_utils_now_s, bs_utils_now_ms, bs_utils_now_float,
#   bs_utils_stamp, bs_utils_log_stamp; в bash и zsh — ещё и прежние utils::human_size, utils::head_bytes,
#   utils::now_s, utils::now_ms, utils::now_float, utils::stamp, utils::log_stamp.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard FMT || return 0

# Человеческий размер: байты или строка с суффиксом (12288K, 3GiB) → "12.0 MiB".
# @description Human-readable size: bytes or suffixed string → "12.0 KiB".
# @description Человеческий размер: байты или строка с суффиксом → "12.0 KiB".
# @param $1 size: plain bytes or suffixed (K/M/G/T, KiB/MiB/GiB) / размер
# @stdout normalized size / нормализованный размер
bs_utils_human_size() {
  __bs_fmt_v=${1:-0}
  __bs_fmt_mult=1
  case "$__bs_fmt_v" in
    *TiB) __bs_fmt_v=${__bs_fmt_v%TiB}; __bs_fmt_mult=1099511627776 ;;
    *GiB) __bs_fmt_v=${__bs_fmt_v%GiB}; __bs_fmt_mult=1073741824 ;;
    *MiB) __bs_fmt_v=${__bs_fmt_v%MiB}; __bs_fmt_mult=1048576 ;;
    *KiB) __bs_fmt_v=${__bs_fmt_v%KiB}; __bs_fmt_mult=1024 ;;
    *TB)  __bs_fmt_v=${__bs_fmt_v%TB};  __bs_fmt_mult=1099511627776 ;;
    *GB)  __bs_fmt_v=${__bs_fmt_v%GB};  __bs_fmt_mult=1073741824 ;;
    *MB)  __bs_fmt_v=${__bs_fmt_v%MB};  __bs_fmt_mult=1048576 ;;
    *KB)  __bs_fmt_v=${__bs_fmt_v%KB};  __bs_fmt_mult=1024 ;;
    *T)   __bs_fmt_v=${__bs_fmt_v%T};   __bs_fmt_mult=1099511627776 ;;
    *G)   __bs_fmt_v=${__bs_fmt_v%G};   __bs_fmt_mult=1073741824 ;;
    *M)   __bs_fmt_v=${__bs_fmt_v%M};   __bs_fmt_mult=1048576 ;;
    *K)   __bs_fmt_v=${__bs_fmt_v%K};   __bs_fmt_mult=1024 ;;
    *B)   __bs_fmt_v=${__bs_fmt_v%B} ;;
  esac
  # пробелы внутри убираем (было ${v// /}) / drop the spaces (it was ${v// /})
  __bs_fmt_v=$(printf '%s' "$__bs_fmt_v" | tr -d ' ')
  case "$__bs_fmt_v" in
    ''|*[!0-9]*)
      printf '%s\n' "${1:-0}"
      return 0 ;;
  esac
  # Умножаем в awk, а не в $(( )): арифметика mksh 32-битная, 3 GiB в ней переполняется
  # We multiply in awk, not in $(( )): mksh arithmetic is 32-bit, 3 GiB overflows in it
  awk -v n="$__bs_fmt_v" -v m="$__bs_fmt_mult" 'BEGIN {
      split("B KiB MiB GiB TiB", u)
      n = n * m
      i = 1
      while (n >= 1024 && i < 5) { n /= 1024; i++ }
      printf "%.1f %s\n", n, u[i]
    }'
}

# Ограниченное чтение файла (первые N байт).
# Заменяет идиому: head -c N -- file с проверкой существования файла
# @description Read the first N bytes of a file (existence-checked).
# @description Прочитать первые N байт файла (с проверкой существования).
# @param $1 file path / путь к файлу
# @param $2 max bytes / максимум байт
# @stdout first N bytes / первые N байт
bs_utils_head_bytes() {
  __bs_fmt_file=${1:?file required}
  __bs_fmt_max=${2:-4000}
  [ -f "$__bs_fmt_file" ] || return 1
  head -c "$__bs_fmt_max" -- "$__bs_fmt_file"
  return 0
}

# @description Current unix time in seconds (epoch).
# @description Текущее время в секундах (epoch).
# @stdout секунды с начала эпохи
bs_utils_now_s() {
  date +%s
}

# Текущее время в миллисекундах (epoch).
# Заменяет идиому: date +%s%3N
# @description Current unix time in milliseconds (epoch).
# @description Текущее время в миллисекундах (epoch).
# @stdout миллисекунды с начала эпохи
bs_utils_now_ms() {
  # EPOCHREALTIME есть в bash 5, ksh93 и zsh (zsh/datetime); иначе date / EPOCHREALTIME exists in bash 5, ksh93 and zsh (zsh/datetime); date otherwise
  # shellcheck disable=SC3028  # EPOCHREALTIME необязательна: пусто там, где её нет / optional: empty where it does not exist
  __bs_fmt_now=$(printf '%s' "${EPOCHREALTIME:-}" | tr -cd '0-9')
  if [ "${#__bs_fmt_now}" -gt 6 ]; then
    printf '%s\n' "${__bs_fmt_now%???}"
    return 0
  fi
  __bs_fmt_now=$(date +%s%3N 2>/dev/null) || __bs_fmt_now=""
  case "$__bs_fmt_now" in
    ''|*[!0-9]*) printf '%s000\n' "$(date +%s)" ;;
    *) printf '%s\n' "$__bs_fmt_now" ;;
  esac
}

# Текущее время в секундах с дробной частью (для интервалов через bc/awk).
# Заменяет идиому: date +%s.%N
# @description Current unix time in seconds with fractional part (epoch).
# @description Текущее время в секундах с дробной частью (epoch).
# @stdout секунды с наносекундной дробной частью
bs_utils_now_float() {
  date +%s.%N
}

# Метка времени для имён файлов: YYYYMMDD_HHMMSS.
# Заменяет идиому: date +%Y%m%d_%H%M%S
# @description Timestamp for filenames: YYYYMMDD_HHMMSS.
# @description Метка времени для имён файлов: YYYYMMDD_HHMMSS.
# @stdout timestamp, безопасный для имён файлов
bs_utils_stamp() {
  date +%Y%m%d_%H%M%S
}

# Человекочитаемая метка времени для логов: "YYYY-MM-DD HH:MM:SS".
# Заменяет идиому: date '+%Y-%m-%d %H:%M:%S'
# @description Human-readable timestamp for logs: "YYYY-MM-DD HH:MM:SS".
# @description Человекочитаемая метка времени для логов: "YYYY-MM-DD HH:MM:SS".
# @stdout timestamp для логов
bs_utils_log_stamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

bs_shell_alias bs_utils_human_size utils::human_size
bs_shell_alias bs_utils_head_bytes utils::head_bytes
bs_shell_alias bs_utils_now_s utils::now_s
bs_shell_alias bs_utils_now_ms utils::now_ms
bs_shell_alias bs_utils_now_float utils::now_float
bs_shell_alias bs_utils_stamp utils::stamp
bs_shell_alias bs_utils_log_stamp utils::log_stamp
