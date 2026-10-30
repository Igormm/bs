#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: массивы и словари на переменных и eval, без массивов, declare -A, nameref, ${!x} и [[ ]] / valid POSIX sh: arrays and maps built on variables and eval, with no arrays, declare -A, namerefs, ${!x} or [[ ]]
# @tier core — builtins only; works everywhere
#
# core/data.sh — массивы и словари для оболочек, у которых их нет (dash, ash)
# core/data.sh — arrays and maps for shells that have none (dash, ash)
#
# ЗАЧЕМ / WHY
#   В POSIX sh нет массивов и ассоциативных массивов, а ядру BS они нужны (список
#   загруженных модулей, стек очистки, конфигурация, параметры скрипта). Этот модуль даёт
#   им замену, которая работает в dash, ash, ksh, mksh, zsh и bash одинаково.
#   POSIX sh has no arrays or associative arrays, and the BS kernel needs them (the list of
#   loaded modules, the cleanup stack, the configuration, script parameters). This module
#   gives it a replacement that works the same in dash, ash, ksh, mksh, zsh and bash.
#
# УСТРОЙСТВО / LAYOUT
#   Массив NAME — переменные __bs_dat_a_NAME__0, __1, … и счётчик __bs_dat_a_NAME__n.
#   Словарь NAME — переменная __bs_dat_m_NAME__<ключ> на каждый ключ (ключ кодируется:
#   всё, кроме букв и цифр, становится _<hex>_, поэтому ключ может содержать что угодно) и
#   массив ключей mk_NAME, который хранит порядок вставки.
#   An array NAME is the variables __bs_dat_a_NAME__0, __1, … and a counter
#   __bs_dat_a_NAME__n. A map NAME is one variable __bs_dat_m_NAME__<key> per key (the key is
#   encoded: everything but letters and digits becomes _<hex>_, so a key may hold anything)
#   and a key array mk_NAME that keeps the insertion order.
#
# ПРАВИЛА / RULES
#   * Имя массива или словаря — [A-Za-z][A-Za-z0-9_]*, без «__» и без «_» на конце.
#     A name is [A-Za-z][A-Za-z0-9_]*, with no "__" and no trailing "_".
#   * Индексы с нуля; отрицательный индекс считается с конца. / Indexes start at 0; a
#     negative index counts from the end.
#   * Результат функции — в stdout (одна строка на значение). Статус 1 — «нет такого».
#     A function's result goes to stdout. Status 1 means "no such element".
#   * bs_arr_each и bs_map_each можно вызывать из своих обратных вызовов (вложенность считается).
#     bs_arr_each and bs_map_each may be called from their own callbacks (nesting is counted).
#
# ИМЕНА / NAMES: пространство bs_ (bs_arr_*, bs_map_*, bs_quote). Старые arr::* и map::* из
#   lib/compat/lang.sh работают с настоящими массивами bash и остаются как есть.
#   Namespace bs_ (bs_arr_*, bs_map_*, bs_quote). The old arr::* and map::* of lib/compat/lang.sh work
#   on real bash arrays and stay as they are.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# shellcheck disable=SC2154  # __bs_dat_out/__bs_dat_cur присваиваются через eval, ShellCheck их не видит / assigned through eval, which ShellCheck cannot follow
bs_guard DATA || return 0

# Dependencies / Зависимости
bs_source_relative "var.sh"

__bs_dat_depth=0

# Служебное / Helpers

# @private
# @description Проверить имя массива или словаря / Check an array or map name
# @param $1 name / имя
bs_data_check() {
  case "${1:-}" in
    ''|[!A-Za-z]*|*[!A-Za-z0-9_]*|*__*|*_)
      printf 'bs_data: invalid name: %s\n' "${1:-}" >&2
      return 2 ;;
  esac
  return 0
}

# Слоты массива NAME — переменные __bs_dat_a_NAME__<индекс>, счётчик — слот «n». Только эти пять
# помощников знают такую запись и зовут eval с именем; имя к ним приходит уже проверенным.
# The slots of an array NAME are the variables __bs_dat_a_NAME__<index>, the counter is the slot "n".
# Only these five helpers know that spelling and call eval with a name; the name reaches them checked.

# @private
# @description Длина массива → __bs_dat_n (0, если массива нет) / The length of an array → __bs_dat_n (0 if there is none)
# @param $1 name / имя
bs_data_len_of() {
  eval "__bs_dat_n=\${__bs_dat_a_${1}__n:-0}"
}

# @private
# @description Записать длину массива / Set the length of an array
# @param $1 name / имя
# @param $2 length / длина
bs_data_set_len() {
  eval "__bs_dat_a_${1}__n=${2}"
}

# @private
# @description Элемент по номеру слота → __bs_dat_cur / The element in a slot → __bs_dat_cur
# @param $1 name / имя
# @param $2 slot index (0..n-1) / номер слота
bs_data_get_at() {
  eval "__bs_dat_cur=\${__bs_dat_a_${1}__${2}}"
}

# @private
# @description Записать значение в слот / Put a value into a slot
# @param $1 name / имя
# @param $2 slot index / номер слота
# @param $3 value / значение
bs_data_put_at() {
  eval "__bs_dat_a_${1}__${2}=\${3}"
}

# @private
# @description Удалить слот (слот «n» — счётчик) / Remove a slot (the slot "n" is the counter)
# @param $1 name / имя
# @param $2 slot index or n / номер слота или n
bs_data_drop_at() {
  eval "unset __bs_dat_a_${1}__${2}"
}

# @private
# @description Взять строку в одинарные кавычки в __bs_dat_qo (без вывода) / Single-quote a string into __bs_dat_qo (no output)
# @param $1 string / строка
bs_quote_to() {
  __bs_dat_qs=${1-}
  # Частый случай — без апострофов: кавычить нечего / common case — no single
  # quotes: nothing to escape
  case "$__bs_dat_qs" in
    *\'*) ;;
    *) __bs_dat_qo=$__bs_dat_qs; return 0 ;;
  esac
  __bs_dat_qo=''
  while :; do
    case "$__bs_dat_qs" in
      *\'*)
        __bs_dat_qo="${__bs_dat_qo}${__bs_dat_qs%%\'*}'\\''"
        __bs_dat_qs=${__bs_dat_qs#*\'} ;;
      *)
        __bs_dat_qo="${__bs_dat_qo}${__bs_dat_qs}"
        break ;;
    esac
  done
}

# @description Взять строку в одинарные кавычки так, чтобы eval вернул её как есть / Single-quote a string so eval gives it back unchanged
# @param $1 string / строка
# @stdout quoted string / строка в кавычках
bs_quote() {
  bs_quote_to "${1-}"
  printf "'%s'" "$__bs_dat_qo"
}

# @private
# @description Закодировать ключ в безопасную часть имени переменной; результат в __bs_dat_enc / Encode a key into a safe part of a variable name; the result is in __bs_dat_enc
# @param $1 key / ключ
bs_data_enc() {
  __bs_dat_ek=${1-}
  __bs_dat_enc=''
  if [ -z "$__bs_dat_ek" ]; then
    __bs_dat_enc='_E_'
    return 0
  fi
  while [ -n "$__bs_dat_ek" ]; do
    __bs_dat_rest=${__bs_dat_ek#?}
    __bs_dat_ch=${__bs_dat_ek%"$__bs_dat_rest"}
    __bs_dat_ek=$__bs_dat_rest
    case "$__bs_dat_ch" in
      [A-Za-z0-9]) __bs_dat_enc="${__bs_dat_enc}${__bs_dat_ch}" ;;
      # частые символы ключей без форка (пути модулей, имена) / common key characters without a fork (module paths, names)
      /) __bs_dat_enc="${__bs_dat_enc}_2F_" ;;
      .) __bs_dat_enc="${__bs_dat_enc}_2E_" ;;
      _) __bs_dat_enc="${__bs_dat_enc}_5F_" ;;
      -) __bs_dat_enc="${__bs_dat_enc}_2D_" ;;
      :) __bs_dat_enc="${__bs_dat_enc}_3A_" ;;
      ' ') __bs_dat_enc="${__bs_dat_enc}_20_" ;;
      *) __bs_dat_enc="${__bs_dat_enc}_$(printf '%X' "'$__bs_dat_ch")_" ;;
    esac
  done
}

# Массивы / Arrays

# @description Число элементов / Number of elements
# @param $1 name / имя
bs_arr_len() {
  bs_data_check "$1" || return 2
  bs_data_len_of "$1"
  printf '%s\n' "$__bs_dat_n"
}

# @description Добавить элементы в конец / Append elements
# @param $1 name / имя
# @param $@ values / значения
bs_arr_push() {
  bs_data_check "$1" || return 2
  __bs_dat_nm=$1
  shift
  bs_data_len_of "$__bs_dat_nm"
  for __bs_dat_v in "$@"; do
    bs_data_put_at "$__bs_dat_nm" "$__bs_dat_n" "$__bs_dat_v"
    __bs_dat_n=$((__bs_dat_n + 1))
  done
  bs_data_set_len "$__bs_dat_nm" "$__bs_dat_n"
}

# @description Очистить массив (имя остаётся допустимым) / Clear an array
# @param $1 name / имя
bs_arr_clear() {
  bs_data_check "$1" || return 2
  __bs_dat_nm=$1
  bs_data_len_of "$__bs_dat_nm"
  __bs_dat_i=0
  while [ "$__bs_dat_i" -lt "$__bs_dat_n" ]; do
    bs_data_drop_at "$__bs_dat_nm" "$__bs_dat_i"
    __bs_dat_i=$((__bs_dat_i + 1))
  done
  bs_data_drop_at "$__bs_dat_nm" n   # слот «n» — счётчик / the slot "n" is the counter
  return 0
}

# @description Заменить содержимое значениями / Replace the content with values
# @param $1 name / имя
# @param $@ values / значения
bs_arr_new() {
  bs_data_check "$1" || return 2
  __bs_dat_nn=$1
  shift
  bs_arr_clear "$__bs_dat_nn"
  bs_arr_push "$__bs_dat_nn" "$@"
}

# @private
# @description Привести индекс к 0..n-1; результат в __bs_dat_idx; статус 1 — вне диапазона / Normalise an index to 0..n-1; the result is in __bs_dat_idx; status 1 means out of range
# @param $1 name / имя
# @param $2 index (negative counts from the end) / индекс
# @param $3 allow n (append position): 1 / разрешить позицию n (вставка в конец)
bs_arr_index() {
  bs_data_len_of "$1"
  case "${2:-}" in
    ''|-|*[!0-9-]*|?*-*) return 1 ;;
  esac
  __bs_dat_idx=$2
  if [ "$__bs_dat_idx" -lt 0 ]; then
    __bs_dat_idx=$((__bs_dat_n + __bs_dat_idx))
  fi
  [ "$__bs_dat_idx" -ge 0 ] || return 1
  if [ "$__bs_dat_idx" -lt "$__bs_dat_n" ]; then return 0; fi
  [ "${3:-0}" = 1 ] && [ "$__bs_dat_idx" -eq "$__bs_dat_n" ]
}

# @description Элемент по индексу: в stdout или в переменную $3 (без подоболочки) / The element at an index: to stdout or into the variable $3 (no subshell)
# @param $1 name / имя
# @param $2 index / индекс
# @param $3 variable for the result, otherwise stdout / переменная для результата, иначе stdout
bs_arr_get() {
  bs_data_check "$1" || return 2
  bs_arr_index "$1" "$2" || return 1
  bs_data_get_at "$1" "$__bs_dat_idx"
  __bs_dat_out=$__bs_dat_cur
  bs_data_ret "${3:-}"
}

# @description Записать элемент по индексу (индекс равный длине — добавление) / Set an element (an index equal to the length appends)
# @param $1 name / имя
# @param $2 index / индекс
# @param $3 value / значение
bs_arr_set() {
  bs_data_check "$1" || return 2
  __bs_dat_nm=$1
  __bs_dat_sv=${3-}
  bs_arr_index "$__bs_dat_nm" "$2" 1 || return 1
  bs_data_put_at "$__bs_dat_nm" "$__bs_dat_idx" "$__bs_dat_sv"
  if [ "$__bs_dat_idx" -eq "$__bs_dat_n" ]; then
    bs_data_set_len "$__bs_dat_nm" $((__bs_dat_n + 1))
  fi
}

# @private
# @description Отдать результат: в переменную $1 (без подоболочки) или в stdout / Hand out a result: into the variable $1 (no subshell) or to stdout
# @param $1 variable name or empty / имя переменной или пусто
bs_data_ret() {
  if [ -n "${1:-}" ]; then
    bs_var_set "$1" "$__bs_dat_out"
  else
    printf '%s\n' "$__bs_dat_out"
  fi
}

# @description Снять последний элемент и вернуть его; НЕ вызывайте как $(...), состояние останется в подоболочке — берите результат в переменную / Remove the last element and return it; do NOT call it as $(...), the change stays in the subshell — take the result into a variable
# @param $1 name / имя
# @param $2 variable for the result, otherwise stdout / переменная для результата, иначе stdout
bs_arr_pop() {
  bs_data_check "$1" || return 2
  __bs_dat_nm=$1
  __bs_dat_rv=${2:-}
  bs_data_len_of "$__bs_dat_nm"
  [ "$__bs_dat_n" -gt 0 ] || return 1
  __bs_dat_n=$((__bs_dat_n - 1))
  bs_data_get_at "$__bs_dat_nm" "$__bs_dat_n"
  __bs_dat_out=$__bs_dat_cur
  bs_data_drop_at "$__bs_dat_nm" "$__bs_dat_n"
  bs_data_set_len "$__bs_dat_nm" "$__bs_dat_n"
  bs_data_ret "$__bs_dat_rv"
}

# @description Снять первый элемент и вернуть его (результат — в переменную, см. bs_arr_pop) / Remove the first element and return it (take the result into a variable, see bs_arr_pop)
# @param $1 name / имя
# @param $2 variable for the result, otherwise stdout / переменная для результата, иначе stdout
bs_arr_shift() {
  bs_data_check "$1" || return 2
  __bs_dat_nm=$1
  __bs_dat_rv=${2:-}
  bs_data_len_of "$__bs_dat_nm"
  [ "$__bs_dat_n" -gt 0 ] || return 1
  bs_data_get_at "$__bs_dat_nm" 0
  __bs_dat_out=$__bs_dat_cur
  __bs_dat_i=1
  while [ "$__bs_dat_i" -lt "$__bs_dat_n" ]; do
    bs_data_get_at "$__bs_dat_nm" "$__bs_dat_i"
    bs_data_put_at "$__bs_dat_nm" $((__bs_dat_i - 1)) "$__bs_dat_cur"
    __bs_dat_i=$((__bs_dat_i + 1))
  done
  __bs_dat_n=$((__bs_dat_n - 1))
  bs_data_drop_at "$__bs_dat_nm" "$__bs_dat_n"
  bs_data_set_len "$__bs_dat_nm" "$__bs_dat_n"
  bs_data_ret "$__bs_dat_rv"
}

# @description Убрать элемент по индексу, сдвинув остальные / Remove the element at an index and shift the rest
# @param $1 name / имя
# @param $2 index / индекс
bs_arr_remove_at() {
  bs_data_check "$1" || return 2
  __bs_dat_nm=$1
  bs_arr_index "$__bs_dat_nm" "$2" || return 1
  __bs_dat_i=$__bs_dat_idx
  __bs_dat_cnt=$__bs_dat_n
  while [ $((__bs_dat_i + 1)) -lt "$__bs_dat_cnt" ]; do
    bs_data_get_at "$__bs_dat_nm" $((__bs_dat_i + 1))
    bs_data_put_at "$__bs_dat_nm" "$__bs_dat_i" "$__bs_dat_cur"
    __bs_dat_i=$((__bs_dat_i + 1))
  done
  __bs_dat_cnt=$((__bs_dat_cnt - 1))
  bs_data_drop_at "$__bs_dat_nm" "$__bs_dat_cnt"
  bs_data_set_len "$__bs_dat_nm" "$__bs_dat_cnt"
}

# @description Индекс первого элемента, равного значению (1 — нет) / Index of the first element equal to a value (1 — none)
# @param $1 name / имя
# @param $2 value / значение
bs_arr_index_of() {
  bs_data_check "$1" || return 2
  __bs_dat_nm=$1
  __bs_dat_want=${2-}
  bs_data_len_of "$__bs_dat_nm"
  __bs_dat_i=0
  while [ "$__bs_dat_i" -lt "$__bs_dat_n" ]; do
    bs_data_get_at "$__bs_dat_nm" "$__bs_dat_i"
    if [ "$__bs_dat_cur" = "$__bs_dat_want" ]; then
      printf '%s\n' "$__bs_dat_i"
      return 0
    fi
    __bs_dat_i=$((__bs_dat_i + 1))
  done
  return 1
}

# @description Есть ли значение в массиве (статус) / Whether a value is in the array (status)
# @param $1 name / имя
# @param $2 value / значение
bs_arr_contains() {
  bs_arr_index_of "$1" "${2-}" >/dev/null
}

# @description Склеить элементы разделителем / Join the elements with a separator
# @param $1 name / имя
# @param $2 separator, default a space / разделитель, по умолчанию пробел
bs_arr_join() {
  bs_data_check "$1" || return 2
  __bs_dat_nm=$1
  __bs_dat_sep=${2- }
  bs_data_len_of "$__bs_dat_nm"
  __bs_dat_acc=''
  __bs_dat_i=0
  while [ "$__bs_dat_i" -lt "$__bs_dat_n" ]; do
    bs_data_get_at "$__bs_dat_nm" "$__bs_dat_i"
    if [ "$__bs_dat_i" -eq 0 ]; then
      __bs_dat_acc=$__bs_dat_cur
    else
      __bs_dat_acc="${__bs_dat_acc}${__bs_dat_sep}${__bs_dat_cur}"
    fi
    __bs_dat_i=$((__bs_dat_i + 1))
  done
  printf '%s\n' "$__bs_dat_acc"
}

# @private
# @description Собрать команду «set -- элементы» в переменную (без подоболочки) / Build a "set -- elements" command into a variable (no subshell)
# @param $1 name / имя
# @param $2 result variable / переменная результата
bs_arr_to_args_to() {
  bs_data_check "$1" || return 2
  __bs_dat_nm=$1
  bs_data_len_of "$__bs_dat_nm"
  __bs_dat_acc='set --'
  __bs_dat_i=0
  while [ "$__bs_dat_i" -lt "$__bs_dat_n" ]; do
    bs_data_get_at "$__bs_dat_nm" "$__bs_dat_i"
    # bs_quote_to кладёт результат в __bs_dat_qo; без $( ) на каждый элемент
    # bs_quote_to puts the result in __bs_dat_qo; no $( ) per element
    bs_quote_to "$__bs_dat_cur"
    __bs_dat_acc="${__bs_dat_acc} '${__bs_dat_qo}'"
    __bs_dat_i=$((__bs_dat_i + 1))
  done
  bs_var_set "${2:?result variable required}" "$__bs_dat_acc"
}

# @description Напечатать команду «set -- элементы» для eval: eval "$(bs_arr_to_args NAME)" / Print a "set -- elements" command for eval
# @param $1 name / имя
bs_arr_to_args() {
  bs_arr_to_args_to "$1" __bs_dat_args || return
  printf '%s\n' "$__bs_dat_args"
}

# @description Разбить текст по строкам в массив / Split text into lines into an array
# @param $1 name / имя
# @param $2 text / текст
bs_arr_from_lines() {
  bs_data_check "$1" || return 2
  __bs_dat_nn=$1
  __bs_dat_txt=${2-}
  bs_arr_clear "$__bs_dat_nn"
  [ -n "$__bs_dat_txt" ] || return 0
  while :; do
    case "$__bs_dat_txt" in
      *"
"*)
        bs_arr_push "$__bs_dat_nn" "${__bs_dat_txt%%"
"*}"
        __bs_dat_txt=${__bs_dat_txt#*"
"} ;;
      *)
        bs_arr_push "$__bs_dat_nn" "$__bs_dat_txt"
        break ;;
    esac
  done
}

# @description Скопировать массив / Copy an array
# @param $1 source name / исходный
# @param $2 destination name / целевой
bs_arr_copy() {
  bs_data_check "$1" || return 2
  bs_data_check "$2" || return 2
  __bs_dat_src=$1
  __bs_dat_dst=$2
  [ "$__bs_dat_src" = "$__bs_dat_dst" ] && return 0
  # Копируем слоты через штатные помощники: без строки «set -- …» и без
  # повторного кавычения каждого элемента (раньше был fork на элемент).
  # Copy the slots via the regular helpers: no "set -- …" string and no
  # re-quoting of every element (that used to fork per element).
  bs_arr_clear "$__bs_dat_dst"
  bs_data_len_of "$__bs_dat_src"
  __bs_dat_cnt=$__bs_dat_n
  __bs_dat_i=0
  while [ "$__bs_dat_i" -lt "$__bs_dat_cnt" ]; do
    bs_data_get_at "$__bs_dat_src" "$__bs_dat_i"
    bs_data_put_at "$__bs_dat_dst" "$__bs_dat_i" "$__bs_dat_cur"
    __bs_dat_i=$((__bs_dat_i + 1))
  done
  bs_data_set_len "$__bs_dat_dst" "$__bs_dat_cnt"
  return 0
}

# @description Вызвать команду для каждого элемента: КОМАНДА ЭЛЕМЕНТ / Call a command for each element: COMMAND ELEMENT
# @param $1 name / имя
# @param $2 command (a function name) / команда (имя функции)
bs_arr_each() {
  bs_data_check "$1" || return 2
  __bs_dat_depth=$((__bs_dat_depth + 1))
  eval "__bs_dat_cmd_${__bs_dat_depth}=\${2:-}"
  eval "$(bs_arr_to_args "$1")"
  for __bs_dat_item in "$@"; do
    eval "\"\${__bs_dat_cmd_${__bs_dat_depth}}\" \"\$__bs_dat_item\""
  done
  __bs_dat_depth=$((__bs_dat_depth - 1))
}

# Словари / Maps

# @private
# @description Имя переменной значения ключа → __bs_dat_var / The variable name of a key's value → __bs_dat_var
# @param $1 map / словарь
# @param $2 key / ключ
bs_map_var() {
  bs_data_enc "${2-}"
  __bs_dat_var="__bs_dat_m_${1}__${__bs_dat_enc}"
}

# Переменная значения ключа — __bs_dat_var (её задаёт bs_map_var); читают и пишут её четыре помощника.
# The variable of a key's value is __bs_dat_var (bs_map_var sets it); four helpers read and write it.

# @private
# @description Задана ли переменная значения (статус) / Whether the value variable is set (status)
bs_data_var_is_set() {
  eval "[ \"\${${__bs_dat_var}+x}\" = x ]"
}

# @private
# @description Значение ключа → __bs_dat_out / The value of the key → __bs_dat_out
bs_data_var_read() {
  eval "__bs_dat_out=\${${__bs_dat_var}}"
}

# @private
# @description Записать значение ключа / Write the value of the key
# @param $1 value / значение
bs_data_var_write() {
  eval "${__bs_dat_var}=\${1}"
}

# @private
# @description Удалить значение ключа / Remove the value of the key
bs_data_var_drop() {
  eval "unset ${__bs_dat_var}"
}

# @description Есть ли ключ (статус) / Whether a key exists (status)
# @param $1 map / словарь
# @param $2 key / ключ
bs_map_has() {
  bs_data_check "$1" || return 2
  bs_map_var "$1" "${2-}"
  bs_data_var_is_set
}

# @description Записать значение по ключу / Set a value by key
# @param $1 map / словарь
# @param $2 key / ключ
# @param $3 value / значение
bs_map_set() {
  bs_data_check "$1" || return 2
  __bs_dat_mn=$1
  __bs_dat_mk=${2-}
  __bs_dat_mv=${3-}
  # bs_map_var один раз: bs_map_has кодировал ключ повторно, а bs_map_var
  # снова его кодировал после возврата.
  # bs_map_var once: bs_map_has encoded the key again, and bs_map_var
  # encoded it once more after it returned.
  bs_map_var "$__bs_dat_mn" "$__bs_dat_mk"
  if ! bs_data_var_is_set; then
    bs_arr_push "mk_${__bs_dat_mn}" "$__bs_dat_mk"
  fi
  bs_data_var_write "$__bs_dat_mv"
}

# @description Значение по ключу; нет ключа — статус 1 (или значение по умолчанию, если оно дано) / The value by key; a missing key is status 1 (or the default if given)
# @param $1 map / словарь
# @param $2 key / ключ
# @param $3 default (optional) / значение по умолчанию (необязательно)
bs_map_get() {
  bs_data_check "$1" || return 2
  if bs_map_has "$1" "${2-}"; then
    bs_data_var_read
    printf '%s\n' "$__bs_dat_out"
    return 0
  fi
  if [ $# -ge 3 ]; then
    printf '%s\n' "$3"
    return 0
  fi
  return 1
}

# @description Положить значение по ключу в переменную (без вывода и подоболочки); нет ключа — статус 1 / Put the value by key into a variable (no output, no subshell); a missing key is status 1
# @param $1 map / словарь
# @param $2 key / ключ
# @param $3 variable name / имя переменной
bs_map_get_to() {
  bs_data_check "$1" || return 2
  # bs_map_var один раз вместо bs_map_has + повторного кодирования ключа
  # bs_map_var once instead of bs_map_has + encoding the key again
  bs_map_var "$1" "${2-}"
  bs_data_var_is_set || return 1
  bs_data_var_read
  bs_data_ret "${3-}"
}

# @description Удалить ключ / Remove a key
# @param $1 map / словарь
# @param $2 key / ключ
bs_map_remove() {
  bs_data_check "$1" || return 2
  __bs_dat_mn=$1
  __bs_dat_mk=${2-}
  bs_map_has "$__bs_dat_mn" "$__bs_dat_mk" || return 1
  bs_data_var_drop
  __bs_dat_pos=$(bs_arr_index_of "mk_${__bs_dat_mn}" "$__bs_dat_mk") || return 0
  bs_arr_remove_at "mk_${__bs_dat_mn}" "$__bs_dat_pos"
}

# @description Число ключей / The number of keys
# @param $1 map / словарь
bs_map_count() {
  bs_data_check "$1" || return 2
  bs_arr_len "mk_${1}"
}

# @description Положить ключи (в порядке вставки) в массив / Put the keys (in insertion order) into an array
# @param $1 map / словарь
# @param $2 array name / имя массива
bs_map_keys_to() {
  bs_data_check "$1" || return 2
  bs_data_check "$2" || return 2
  bs_arr_copy "mk_${1}" "$2"
}

# @description Напечатать ключи по одному в строке (ключи с переводом строки — через bs_map_keys_to) / Print the keys one per line (keys with a newline: use bs_map_keys_to)
# @param $1 map / словарь
bs_map_keys() {
  bs_data_check "$1" || return 2
  __bs_dat_mn=$1
  bs_data_len_of "mk_${__bs_dat_mn}"
  __bs_dat_i=0
  while [ "$__bs_dat_i" -lt "$__bs_dat_n" ]; do
    bs_data_get_at "mk_${__bs_dat_mn}" "$__bs_dat_i"
    printf '%s\n' "$__bs_dat_cur"
    __bs_dat_i=$((__bs_dat_i + 1))
  done
}

# @description Очистить словарь / Clear a map
# @param $1 map / словарь
bs_map_clear() {
  bs_data_check "$1" || return 2
  __bs_dat_mn=$1
  eval "$(bs_arr_to_args "mk_${__bs_dat_mn}")"
  for __bs_dat_key in "$@"; do
    bs_map_var "$__bs_dat_mn" "$__bs_dat_key"
    bs_data_var_drop
  done
  bs_arr_clear "mk_${__bs_dat_mn}"
}

# @description Вызвать команду для каждой пары: КОМАНДА КЛЮЧ ЗНАЧЕНИЕ / Call a command for each pair: COMMAND KEY VALUE
# @param $1 map / словарь
# @param $2 command (a function name) / команда (имя функции)
bs_map_each() {
  bs_data_check "$1" || return 2
  __bs_dat_depth=$((__bs_dat_depth + 1))
  eval "__bs_dat_mcmd_${__bs_dat_depth}=\${2:-}"
  eval "__bs_dat_mmap_${__bs_dat_depth}=\${1}"
  eval "$(bs_arr_to_args "mk_${1}")"
  for __bs_dat_key in "$@"; do
    eval "bs_map_var \"\${__bs_dat_mmap_${__bs_dat_depth}}\" \"\$__bs_dat_key\""
    bs_data_var_read
    __bs_dat_val=$__bs_dat_out
    eval "\"\${__bs_dat_mcmd_${__bs_dat_depth}}\" \"\$__bs_dat_key\" \"\$__bs_dat_val\""
  done
  __bs_dat_depth=$((__bs_dat_depth - 1))
}
