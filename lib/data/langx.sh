#!/usr/bin/env bs
# shellcheck shell=bash
# lib/data/langx.sh — language extensions (C23 / C++23 / C++26 inspired)
# lib/data/langx.sh — языковые расширения (по мотивам C23 / C++23 / C++26)

# @depends core/lang, core/const, core/logger, core/utils
# @tier core

# Source Guard
bs::guard "LIB_DATA_LANGX" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh" "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# ==========================================
# Language extensions / Языковые расширения
#
# Contracts (C++26 [[pre:]]/[[post:]]), expected-style capture
# (C++23 std::expected), formatting (C++23 std::print), reflection
# (C++26 std::meta), parallel execution (C++26 std::execution),
# number parsing (C23 digit separators / binary literals).
# Контракты (C++26 [[pre:]]/[[post:]]), захват в стиле expected
# (C++23 std::expected), форматирование (C++23 std::print), рефлексия
# (C++26 std::meta), параллельное выполнение (C++26 std::execution),
# разбор чисел (C23 разделители цифр / бинарные литералы).
# ==========================================

# @description Precondition: abort the function if the condition is false.
# @description Предусловие: прервать функцию, если условие ложно
#   (C++26 [[pre:]]). The condition is a string evaluated in the caller's
#   scope — reference variables BY NAME: bs::pre 'is::number "$port"'.
#   Evaluated with eval — only developer-authored strings.
#   Условие — строка, вычисляемая в скоупе вызывающего — ссылайтесь на
#   переменные ПО ИМЕНИ: bs::pre 'is::number "$port"'.
#   Выполняется через eval — только строки от разработчика.
# @param $1 Condition string / Строка-условие
# @param $2 [optional] Message / Сообщение
# @return 0 ok, 1 failed
# @example
#   connect() {
#     bs::pre 'is::not_empty "$host"' "host is required"
#     bs::pre 'is::number "$port"'    "port must be a number"
#     ...
#   }
bs::pre() {
  local -r __px_cond="${1:?condition required}"
  local -r __px_msg="${2:-precondition failed}"
  # shellcheck disable=SC2294
  if ! eval "${__px_cond}"; then
    log::error "PRECONDITION FAILED: ${__px_msg} — ${__px_cond}"
    return 1
  fi
  return 0
}

# @description Postcondition: verify a result before returning
# @description Постусловие: проверить результат перед возвратом
#   (C++26 [[post:]]). Same evaluation rules as bs::pre.
# @param $1 Condition string / Строка-условие
# @param $2 [optional] Message / Сообщение
# @return 0 ok, 1 failed
# @example
#   parse_version() {
#     local out="$(...)"
#     bs::post 'is::not_empty "$out"' "parser must return something"
#     printf '%s\n' "${out}"
#   }
bs::post() {
  local -r __px_cond="${1:?condition required}"
  local -r __px_msg="${2:-postcondition failed}"
  # shellcheck disable=SC2294
  if ! eval "${__px_cond}"; then
    log::error "POSTCONDITION FAILED: ${__px_msg} — ${__px_cond}"
    return 1
  fi
  return 0
}

# @description Run a command, capture stdout into a named variable, keep
#   the exit code (C++23 std::expected pattern).
# @description Выполнить команду, захватить stdout в именованную переменную
#   и сохранить код возврата (паттерн C++23 std::expected).
#   Solves the classic `local out="$(cmd)"` gotcha where `local` masks $?.
#   Решает классическую ловушку `local out="$(cmd)"`, где `local` теряет $?.
# @param $1 Output variable name / Имя выходной переменной
# @param $@ Command and arguments / Команда и аргументы
# @return the command's exit code / код возврата команды
# @example
#   if bs::capture out curl -s "http://..."; then
#     echo "got: ${out}"
#   else
#     echo "failed with: ${out}"
#   fi
bs::capture() {
  local -rn __px_out="${1:?output var name required}"
  shift
  local __px_rc=0
  __px_out="$("$@" 2>/dev/null)" || __px_rc=$?
  return "${__px_rc}"
}

# @description Run a command and emit {code, stdout} as JSON.
# @description Выполнить команду и выдать {code, stdout} как JSON.
#   Requires jq / Требует jq.
# @param $@ Command and arguments / Команда и аргументы
# @stdout one JSON object / один JSON-объект
# @return the command's exit code / код возврата команды
# @example
#   bs::capture_json df -h /tmp
bs::capture_json() {
  local __px_out=""
  local __px_rc=0
  __px_out="$("$@" 2>/dev/null)" || __px_rc=$?
  jq -nc --argjson code "${__px_rc}" --arg stdout "${__px_out}" \
    '{code: $code, stdout: $stdout}'
  return "${__px_rc}"
}

# @description Run functions in parallel, print outputs in order
# @description Запустить функции параллельно, вывести результаты по порядку
#   (C++26 std::execution). Each function runs in a subshell: side effects
#   on variables are lost; stdout is captured per function.
#   Каждая функция выполняется в subshell: побочные эффекты на переменных
#   теряются; stdout захватывается по функциям.
# @param $@ Function names (no arguments) / Имена функций (без аргументов)
# @return 0 all succeeded, 1 at least one failed
# @example
#   bs::parallel my::fetch_a my::fetch_b my::fetch_c
bs::parallel() {
  (( $# > 0 )) || return 1
  local -r __px_tmp="$(mktemp -d)"
  local -i __px_i=0 __px_failed=0
  local __px_fn __px_pid
  local -a __px_pids=() __px_names=("$@")

  for __px_fn in "$@"; do
    if ! is::function "${__px_fn}"; then
      rm -rf "${__px_tmp}"
      return 1
    fi
    "${__px_fn}" > "${__px_tmp}/out.${__px_i}" 2> "${__px_tmp}/err.${__px_i}" &
    __px_pids+=($!)
    __px_i=$(( __px_i + 1 ))
  done

  __px_i=0
  for __px_pid in "${__px_pids[@]}"; do
    if wait "${__px_pid}"; then
      :
    else
      __px_failed=1
    fi
    printf '=== %s ===\n' "${__px_names[__px_i]}"
    cat "${__px_tmp}/out.${__px_i}"
    __px_i=$(( __px_i + 1 ))
  done
  rm -rf "${__px_tmp}"
  return "${__px_failed}"
}

# @description List defined functions matching a glob pattern
# @description Список определённых функций по glob-паттерну
#   (C++26 std::meta reflection). Uses `declare -F` (compgen proved flaky
#   inside eval + pipefail). Pure read/case for the filter.
# @param $1 [optional] Glob pattern, default "*" / Glob-паттерн
# @stdout matching function names, sorted / имена функций, отсортированы
# @example
#   bs::reflect "arr::*"
#   bs::reflect "bs::__*"
bs::reflect() {
  local -r __px_pattern="${1:-*}"
  local __px_fns __px_fn
  __px_fns="$(declare -F | awk '{print $3}' | sort)"
  while IFS= read -r __px_fn; do
    case "${__px_fn}" in
      ${__px_pattern}) printf '%s\n' "${__px_fn}" ;;
    esac
  done <<< "${__px_fns}"
}

# @description Parse a number: C-style bases and digit separators
# @description Разобрать число: C-стиль оснований и разделители цифр
#   (C23: 0b1010, 0xFF, 017, 1_000_000, 1'000). Pure bash arithmetic.
# @param $1 Number literal / Числовой литерал
# @stdout decimal value / десятичное значение
# @return 0 ok, 1 invalid
# @example
#   bs::num "0b1010"     # 10
#   bs::num "1_000_000"  # 1000000
#   bs::num "0xFF"       # 255
bs::num() {
  local __px_s="${1-}"
  if is::empty "${__px_s}"; then
    return 1
  fi
  __px_s="${__px_s//_/}"
  __px_s="${__px_s//\'/}"

  local __px_sign=""
  if [[ "${__px_s}" == -* ]]; then
    __px_sign="-"
    __px_s="${__px_s:1}"
  fi

  local __px_base=10
  case "${__px_s}" in
    0b*|0B*) __px_base=2;  __px_s="${__px_s:2}" ;;
    0x*|0X*) __px_base=16; __px_s="${__px_s:2}" ;;
    0[0-7]*) __px_base=8;  __px_s="${__px_s:1}" ;;
  esac

  if is::empty "${__px_s}"; then
    printf '0\n'
    return 0
  fi
  # Цифры должны соответствовать основанию / Digits must fit the base
  local __px_regex="^[0-9]+$"
  case "${__px_base}" in
    2)  __px_regex="^[01]+$" ;;
    8)  __px_regex="^[0-7]+$" ;;
    16) __px_regex="^[0-9A-Fa-f]+$" ;;
  esac
  [[ "${__px_s}" =~ ${__px_regex} ]] || return 1
  printf '%d\n' "$(( ${__px_sign}${__px_base}#${__px_s} ))"
}

# @description Predicate: integer literal with separators/bases (C23).
# @description Предикат: целочисленный литерал с разделителями/основаниями.
# @param $1 Literal / Литерал
# @return 0 valid, 1 invalid
# @example
#   is::int "0b1010" && ...
is::int() {
  utils::quiet bs::num "${1-}"
}

# @description Predicate: floating-point literal (Go strconv.ParseFloat).
# @description Предикат: литерал с плавающей точкой (Go strconv.ParseFloat).
#   Accepts exponents: 3.14, .5, 2., 1e-3, 2.5E6, -0.5.
# @param $1 Literal / Литерал
# @return 0 valid, 1 invalid
# @example
#   is::float "2.5e-3" && ...
is::float() {
  [[ "${1-}" =~ ^-?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$ ]]
}

# @description Declare integer constants (Go iota).
# @description Объявить целочисленные константы (Go iota).
#   Names become readonly: A=1, B=2, ... (1-based — 0 is the Go zero value).
#   Имена становятся readonly: A=1, B=2, ... (с 1 — 0 это Go zero value).
# @param $1 [optional] Start value, default 1 / Начальное значение
# @param $@ Constant names (SCREAMING_SNAKE recommended) / Имена констант
# @return 0 ok, 1 invalid name
# @example
#   bs::enum STATUS_OK STATUS_FAIL STATUS_UNKNOWN
#   echo "${STATUS_OK}"     # 1
bs::enum() {
  local -i __en_i=1
  if [[ "${1-}" =~ ^-?[0-9]+$ ]]; then
    __en_i="$1"
    shift
  fi
  local __en_name
  for __en_name in "$@"; do
    if ! [[ "${__en_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      log::error "bs::enum: invalid constant name: ${__en_name}"
      return 1
    fi
    readonly "${__en_name}=${__en_i}"
    __en_i=$(( __en_i + 1 ))
  done
}

# @description Random integer in a range (Go math/rand/v2).
# @description Случайное целое в диапазоне (Go math/rand/v2).
#   Bash $RANDOM is 15-bit (0..32767) — the range is limited accordingly.
# @param $1 [optional] MIN, default 0 / минимум
# @param $2 [optional] MAX (inclusive), default 32767 / максимум (включительно)
# @stdout the number / число
# @return 0 ok, 1 invalid range
# @example
#   bs::rand 1 6      # dice
#   bs::rand 100 200
bs::rand() {
  local -i min="${1:-0}" max="${2:-32767}"
  (( max >= min )) || return 1
  local -i span=$(( max - min + 1 ))
  printf '%d\n' "$(( min + RANDOM % span ))"
}

# @description Embed a text file as a bash literal (Go embed).
# @description Встроить текстовый файл как bash-литерал (Go embed).
#   Prints a single-quoted literal with '\'' escapes — evaluate it to
#   define the variable: eval "$(bs::embed file)". The embedded text
#   becomes part of the generated script, exactly like Go's //go:embed.
#   Выводит литерал в одинарных кавычках с '\''-экранированием —
#   вычисляется через eval: eval "$(bs::embed file)". Встроенный текст
#   становится частью сгенерированного скрипта, как //go:embed.
# @param $1 File path / Путь к файлу
# @stdout a bash string literal / bash-литерал
# @return 0 ok, 1 file missing
# @example
#   eval "$(bs::embed "lib/data/example.conf")"
#   # now the variable contains the file content
bs::embed() {
  local -r __px_file="${1:?file required}"
  is::file "${__px_file}" || return 1
  local __px_data
  __px_data="$(cat -- "${__px_file}")"
  printf "'%s'\n" "${__px_data//\'/\'\\\'\'}"
}