#!/usr/bin/env bs
# shellcheck shell=bash
# lib/rfc/csv.sh — RFC 4180: CSV records and fields
# lib/rfc/csv.sh — RFC 4180: записи и поля CSV

# @depends core/lang

# Source Guard
bs::guard "LIB_RFC_CSV" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh"

# ==========================================
# RFC 4180 — CSV
#
# csv::rows    — split text into records (CRLF/LF; quoted multiline fields)
# csv::fields  — split one record into fields (quotes, "" escape, commas)
# csv::rows    — разбить текст на записи (CRLF/LF; многострочные поля)
# csv::fields  — разбить запись на поля (кавычки, экранирование "", запятые)
# ==========================================

# @description Split CSV text into records (RFC 4180 §2).
# @description Разбить текст CSV на записи (RFC 4180 §2).
#   Records are separated by CRLF/LF; quoted fields may contain newlines.
#   Empty records (blank lines) are skipped.
#   Записи разделяются CRLF/LF; кавычки в поле могут содержать переносы.
#   Пустые записи (пустые строки) пропускаются.
# @param $1 CSV text / Текст CSV
# @param $2 Output array name (will be reset) / Имя выходного массива
# @example
#   csv::rows "$(cat data.csv)" records
csv::rows() {
  local -rn __csv_out="${2:?output array name required}"
  local -r __csv_text="${1-}"
  __csv_out=()
  is::empty "${__csv_text}" && return 0

  local __csv_line __csv_record="" __csv_c
  local -i __csv_i __csv_in_quotes=0

  while IFS= read -r __csv_line || [[ -n "${__csv_line}" ]]; do
    __csv_line="${__csv_line%$'\r'}"
    if (( __csv_in_quotes == 1 )); then
      __csv_record+=$'\n'"${__csv_line}"
    else
      __csv_record="${__csv_line}"
    fi
    for (( __csv_i = 0; __csv_i < ${#__csv_line}; __csv_i++ )); do
      [[ "${__csv_line:__csv_i:1}" == '"' ]] && __csv_in_quotes=$(( 1 - __csv_in_quotes ))
    done
    if (( __csv_in_quotes == 0 )) && is::not_empty "${__csv_record}"; then
      __csv_out+=("${__csv_record}")
      __csv_record=""
    fi
  done <<< "${__csv_text}"
  if (( __csv_in_quotes == 1 )); then
    __csv_out+=("${__csv_record}")
  fi
}

# @description Split one CSV record into fields (RFC 4180 §2.4-2.7).
# @description Разбить одну CSV-запись на поля (RFC 4180 §2.4-2.7).
#   Handles: quoted fields, commas inside quotes, "" escaped quotes,
#   empty fields. Обрабатывает: поля в кавычках, запятые внутри кавычек,
#   экранированные кавычки "", пустые поля.
# @param $1 Record (one line of CSV) / Запись (одна строка CSV)
# @param $2 Output array name (will be reset) / Имя выходного массива
# @example
#   csv::fields "a,\"b,c\",\"he said \"\"hi\"\"\"" f
#   # f = (a, b,c, he said "hi")
csv::fields() {
  local -rn __csv_out="${2:?output array name required}"
  local -r __csv_rec="${1-}"
  __csv_out=()

  local __csv_field="" __csv_c
  local -i __csv_i __csv_in_quotes=0
  local -i __csv_n="${#__csv_rec}"

  for (( __csv_i = 0; __csv_i < __csv_n; __csv_i++ )); do
    __csv_c="${__csv_rec:__csv_i:1}"
    if (( __csv_in_quotes == 1 )); then
      if [[ "${__csv_c}" == '"' ]]; then
        if [[ "${__csv_rec:__csv_i + 1:1}" == '"' ]]; then
          __csv_field+='"'
          __csv_i=$(( __csv_i + 1 ))
        else
          __csv_in_quotes=0
        fi
      else
        __csv_field+="${__csv_c}"
      fi
    else
      case "${__csv_c}" in
        '"') __csv_in_quotes=1 ;;
        ',') __csv_out+=("${__csv_field}") ; __csv_field="" ;;
        *)   __csv_field+="${__csv_c}" ;;
      esac
    fi
  done
  __csv_out+=("${__csv_field}")
}