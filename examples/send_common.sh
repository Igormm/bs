#!/usr/bin/env bs
# shellcheck shell=bash
# examples/send_common.sh — run directory shared by send_video.sh / send_audio.sh
# examples/send_common.sh — каталог прогона, общий для send_video.sh / send_audio.sh
#
# Both scripts keep everything about one media file in one directory:
#   <output>/<media name>/
#     video.params  audio.params   settings the run was started with
#     video.state   audio.state    checkpoint: where the run stopped
#     video.txt     audio.txt      human-readable report
#     video.jsonl   audio.jsonl    one JSON object per piece, start_ms/end_ms
#     send_video_<time>.log ...    processing logs
# Оба скрипта держат всё об одном медиафайле в одном каталоге (см. выше):
# параметры, точку остановки, отчёт, машинный результат и журналы.

# Source Guard
bs::guard "SEND_COMMON" || return 0

# @description Run directory for a media file: <parent>/<file name without ext>.
# @description Каталог прогона для медиафайла: <родитель>/<имя без расширения>.
# @param $1 Parent directory (--output) / Родительский каталог
# @param $2 Media file / Медиафайл
# @stdout Directory path / Путь каталога
sendrun::dir_for() {
  local -r parent="${1:-.}"
  local name="${2:?media file required}"
  name="${name##*/}"
  if [[ "${name}" == *.* && "${name}" != .* ]]; then
    name="${name%.*}"
  fi
  io::streams::printf '%s/%s' "${parent%/}" "${name}"
}

# @description Make sure the run directory exists; tell if it was there.
# @description Убедиться, что каталог прогона есть; сообщить, был ли он раньше.
# @param $1 Directory / Каталог
# @return 0 the directory already existed, 1 it was created now, 2 on failure
sendrun::ensure_dir() {
  local -r dir="${1:?directory required}"
  if is::dir "${dir}"; then
    if ! is::writable "${dir}"; then
      return 2
    fi
    return 0
  fi
  if [[ -e "${dir}" ]]; then
    return 2
  fi
  if ! utils::quiet_err mkdir -p -- "${dir}"; then
    return 2
  fi
  return 1
}

# @description Absolute path of an existing file.
# @description Абсолютный путь существующего файла.
# @param $1 File / Файл
# @stdout Absolute path / Абсолютный путь
sendrun::abs_path() {
  local -r file="${1:?file required}"
  local dir
  dir="$(cd -- "$(dirname -- "${file}")" && pwd)"
  io::streams::printf '%s/%s' "${dir}" "${file##*/}"
}

# @description sha256 of a text, to tell whether a prompt has changed.
# @description sha256 текста — чтобы понять, изменился ли промпт.
# @param $1 Text / Текст
# @stdout Hex digest / Хеш
sendrun::hash() {
  local sum
  sum="$(io::streams::printf '%s' "${1-}" | sha256sum)"
  io::streams::printf '%s' "${sum%% *}"
}

# @description Read a key=value file into an associative array.
# @description Прочитать файл key=value в ассоциативный массив.
# @param $1 File / Файл
# @param $2 Name of the associative array / Имя ассоциативного массива
# @return 0 if the file was read, 1 if it does not exist
sendrun::kv_read() {
  local -r file="${1:?file required}"
  local -n __map_out="${2:?map name required}"
  local line
  is::file "${file}" || return 1
  while IFS= read -r line || is::not_empty "${line}"; do
    if is::empty "${line}" || [[ "${line}" == '#'* || "${line}" != *=* ]]; then
      continue
    fi
    __map_out["${line%%=*}"]="${line#*=}"
  done < "${file}"
  return 0
}

# @description Write the listed keys of a map as key=value, atomically.
# @description Записать перечисленные ключи массива как key=value, атомарно.
# @param $1 File / Файл
# @param $2 Name of the associative array / Имя ассоциативного массива
# @param $@ Keys in the order to write (from $3) / Ключи по порядку
# @return 0 on success, 1 if the file could not be written
sendrun::kv_write() {
  local -r file="${1:?file required}"
  local -n __map_in="${2:?map name required}"
  shift 2
  local -r tmp="${file}.tmp.$$"
  local key value
  {
    for key in "$@"; do
      # One line per key: a value never carries a line break
      value="${__map_in[${key}]:-}"
      io::streams::print "${key}=${value//$'\n'/ }"
    done
  } > "${tmp}" || return 1
  # Rename within one directory: a reader never sees a half-written file
  mv -f -- "${tmp}" "${file}" || return 1
  return 0
}

# @description Format milliseconds as HH:MM:SS.mmm.
# @description Отформатировать миллисекунды как ЧЧ:ММ:СС.ммм.
# @param $1 Milliseconds / Миллисекунды
# @stdout Time code / Таймкод
sendrun::timecode_ms() {
  local -i ms=0
  if is::number "${1:-0}"; then
    ms="${1:-0}"
  fi
  local -r -i sec=$(( ms / 1000 ))
  io::streams::printf '%02d:%02d:%02d.%03d' \
    "$(( sec / 3600 ))" "$(( (sec % 3600) / 60 ))" "$(( sec % 60 ))" \
    "$(( ms % 1000 ))"
}
