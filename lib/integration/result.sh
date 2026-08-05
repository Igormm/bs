#!/usr/bin/env bash
#
# lib/integration/result.sh — JSON result contract for BS integrations
# lib/integration/result.sh — JSON-контракт результата для интеграций BS
#
# Provides a unified, structured result object for external callers
# (Go backend, HTTP APIs, CI systems) wrapping both external commands and
# internal BS functions.
#
# Usage / Использование:
#   load "lib/integration/result"
#
#   result::run -- ls -la /tmp
#   result::wrap io::files::copy_file "src.txt" "dst.txt"
#   BS_RESULT_FILE=/tmp/out.json result::run -- sleep 1
#
# @depends core/const, core/logger, core/utils, lib/io/streams

# Source Guard / Защита от повторной загрузки
# Load core prerequisites if not already available
if ! declare -f bs::guard >/dev/null 2>&1; then
    source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/prereq.sh"
fi
bs::guard "IO_INTEGRATION_RESULT" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../io/streams.sh"

# Module version / Версия модуля
declare -g IO_INTEGRATION_RESULT_VERSION="1.0.0"

# ==========================================
# Private helpers / Приватные вспомогательные функции
# ==========================================

# @private
# @description Current timestamp in milliseconds.
# @description Текущий timestamp в миллисекундах.
# @stdout milliseconds since epoch
__integration_result::now_ms() {
  date +%s%3N
}

# @private
# @description ISO8601 timestamp.
# @description ISO8601 timestamp.
# @stdout ISO8601 string
__integration_result::iso_timestamp() {
  date -Iseconds
}

# @private
# @description Escape a string for inclusion in JSON (fallback without jq).
# @description Экранировать строку для JSON (fallback без jq).
# @param $1 String to escape
# @stdout escaped string
__integration_result::json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "${s}"
}

# @private
# @description Build a JSON array of strings from arguments.
# @description Собрать JSON-массив строк из аргументов.
# @param $@ arguments
# @stdout JSON array
__integration_result::args_to_json() {
  if utils::has jq; then
    local json
    json=$(printf '%s\n' "$@" | jq -R . | jq -s .)
    if [[ "${json: -1}" == $'\n' ]]; then
      json="${json%?}"
    fi
    printf '%s' "${json}"
    return 0
  fi

  local arg
  local first=1
  local result="["
  for arg in "$@"; do
    if [[ "${first}" -eq 1 ]]; then
      first=0
    else
      result+=","
    fi
    result+="\"$(__integration_result::json_escape "${arg}")\""
  done
  result+="]"
  printf '%s' "${result}"
}

# @private
# @description Build the result JSON object.
# @description Собрать JSON-объект результата.
# @param $1 success (true/false)
# @param $2 exit_code
# @param $3 operation
# @param $4 args_json
# @param $5 data (string or null)
# @param $6 stdout
# @param $7 stderr
# @param $8 message
# @param $9 timestamp
# @param $10 duration_ms
# @stdout JSON result object
__integration_result::build_json() {
  local success="${1:-false}"
  local exit_code="${2:-1}"
  local operation="${3:-}"
  local args_json="${4:-[]}"
  local data="${5:-null}"
  local stdout_data="${6:-}"
  local stderr_data="${7:-}"
  local message="${8:-}"
  local timestamp="${9:-}"
  local duration_ms="${10:-0}"

  if utils::has jq; then
    local data_json
    if [[ "${data}" == "null" ]]; then
      data_json="null"
    else
      data_json=$(printf '%s' "${data}" | jq -R -s .)
      if [[ "${data_json: -1}" == $'\n' ]]; then
        data_json="${data_json%?}"
      fi
    fi

    jq -n \
      --arg success "${success}" \
      --argjson exit_code "${exit_code}" \
      --arg operation "${operation}" \
      --argjson args "${args_json}" \
      --argjson data "${data_json}" \
      --arg stdout "${stdout_data}" \
      --arg stderr "${stderr_data}" \
      --arg message "${message}" \
      --arg timestamp "${timestamp}" \
      --argjson duration_ms "${duration_ms}" \
      '{
        success: ($success == "true"),
        exit_code: $exit_code,
        operation: $operation,
        args: $args,
        data: $data,
        stdout: $stdout,
        stderr: $stderr,
        message: $message,
        timestamp: $timestamp,
        duration_ms: $duration_ms
      }'
  else
    local data_out
    if [[ "${data}" == "null" ]]; then
      data_out="null"
    else
      data_out="\"$(__integration_result::json_escape "${data}")\""
    fi

    printf '{"success":%s,"exit_code":%s,"operation":"%s","args":%s,"data":%s,"stdout":"%s","stderr":"%s","message":"%s","timestamp":"%s","duration_ms":%s}\n' \
      "${success}" \
      "${exit_code}" \
      "$(__integration_result::json_escape "${operation}")" \
      "${args_json}" \
      "${data_out}" \
      "$(__integration_result::json_escape "${stdout_data}")" \
      "$(__integration_result::json_escape "${stderr_data}")" \
      "$(__integration_result::json_escape "${message}")" \
      "${timestamp}" \
      "${duration_ms}"
  fi
}

# @private
# @description Emit JSON to stdout or to BS_RESULT_FILE.
# @description Вывести JSON в stdout или в BS_RESULT_FILE.
# @param $1 JSON string
__integration_result::emit() {
  local json="${1:-}"

  if [[ -n "${BS_RESULT_FILE:-}" ]]; then
    printf '%s\n' "${json}" > "${BS_RESULT_FILE}"
  else
    printf '%s\n' "${json}"
  fi
}

# @private
# @description Run an external command and capture stdout/stderr.
# @description Запустить внешнюю команду и перехватить stdout/stderr.
# @param $@ command and arguments
# @stdout captured stdout / stdout output variable name
# @stderr captured stderr / stderr output variable name
# @return exit code of the command
__integration_result::capture_run() {
  local -n stdout_ref="${1:-}"
  local -n stderr_ref="${2:-}"
  local -n rc_ref="${3:-}"
  shift 3

  local _stdout_tmp
  local _stderr_tmp
  _stdout_tmp="$(mktemp)"
  _stderr_tmp="$(mktemp)"

  local _rc=0
  "$@" >"${_stdout_tmp}" 2>"${_stderr_tmp}" || _rc=$?

  local _stdout_data
  local _stderr_data
  _stdout_data="$(cat "${_stdout_tmp}")"
  _stderr_data="$(cat "${_stderr_tmp}")"
  rm -f -- "${_stdout_tmp}" "${_stderr_tmp}"

  stdout_ref="${_stdout_data}"
  stderr_ref="${_stderr_data}"
  rc_ref="${_rc}"
}

# @private
# @description Call a BS function and capture stdout/stderr.
# @description Вызвать функцию BS и перехватить stdout/stderr.
# @param $1 stdout output variable name
# @param $2 stderr output variable name
# @param $3 rc output variable name
# @param $4 function name
# @param $@ function arguments
__integration_result::capture_wrap() {
  local -n stdout_ref="${1:-}"
  local -n stderr_ref="${2:-}"
  local -n rc_ref="${3:-}"
  local func="${4:-}"
  shift 4

  local _stdout_tmp
  local _stderr_tmp
  _stdout_tmp="$(mktemp)"
  _stderr_tmp="$(mktemp)"

  local _saved_stdout
  local _saved_stderr
  io::streams::save 1 _saved_stdout
  io::streams::save 2 _saved_stderr

  exec 1>"${_stdout_tmp}"
  exec 2>"${_stderr_tmp}"

  local _rc=0
  "${func}" "$@" || _rc=$?

  io::streams::restore "${_saved_stdout}" 1
  io::streams::restore "${_saved_stderr}" 2

  local _stdout_data
  local _stderr_data
  _stdout_data="$(cat "${_stdout_tmp}")"
  _stderr_data="$(cat "${_stderr_tmp}")"
  rm -f -- "${_stdout_tmp}" "${_stderr_tmp}"

  stdout_ref="${_stdout_data}"
  stderr_ref="${_stderr_data}"
  rc_ref="${_rc}"
}

# ==========================================
# Public API / Публичный API
# ==========================================

# @description Build and emit a successful result object.
# @description Собрать и вывести успешный объект результата.
# @param [$1=null] Data payload / Полезная нагрузка
# @param [$2="OK"] Message / Сообщение
# @return 0
# @example
#   result::ok "file copied" "Operation completed"
result::ok() {
  local data="${1:-null}"
  local message="${2:-OK}"
  local timestamp
  timestamp="$(__integration_result::iso_timestamp)"

  local json
  json="$(__integration_result::build_json \
    "true" 0 "result::ok" "[]" "${data}" "" "" "${message}" "${timestamp}" 0)"

  __integration_result::emit "${json}"
  return 0
}

# @description Build and emit an error result object.
# @description Собрать и вывести объект результата с ошибкой.
# @param $1 Exit code / Код возврата
# @param [$2="Error"] Message / Сообщение
# @param [$3=null] Data payload / Полезная нагрузка
# @return exit code
# @example
#   result::error "${LIB_ERROR_FILE_NOT_FOUND}" "Source not found"
result::error() {
  local code="${1:-${E_ERROR}}"
  local message="${2:-Error}"
  local data="${3:-null}"
  local timestamp
  timestamp="$(__integration_result::iso_timestamp)"

  local json
  json="$(__integration_result::build_json \
    "false" "${code}" "result::error" "[]" "${data}" "" "" "${message}" "${timestamp}" 0)"

  __integration_result::emit "${json}"
  return "${code}"
}

# @description Run an external command and emit a structured JSON result.
# @description Запустить внешнюю команду и вывести структурированный JSON-результат.
# @param $@ command and arguments (use -- to separate options) /
#   Команда и аргументы (-- отделяет опции)
# @return exit code of the command / Код возврата команды
# @example
#   result::run -- ls -la /tmp
#   result::run -- wget https://example.com/file.iso
result::run() {
  local -a cmd=("$@")

  if [[ ${#cmd[@]} -eq 0 ]]; then
    result::error "${E_INVALID}" "No command specified"
    return "${E_INVALID}"
  fi

  if [[ "${cmd[0]}" == "--" ]]; then
    cmd=("${cmd[@]:1}")
  fi

  if [[ ${#cmd[@]} -eq 0 ]]; then
    result::error "${E_INVALID}" "No command specified"
    return "${E_INVALID}"
  fi

  local operation="${cmd[0]}"

  local start_ms
  start_ms="$(__integration_result::now_ms)"

  local stdout_data
  local stderr_data
  local rc
  __integration_result::capture_run stdout_data stderr_data rc "${cmd[@]}"

  local end_ms
  local duration_ms
  end_ms="$(__integration_result::now_ms)"
  duration_ms=$((end_ms - start_ms))

  local success="true"
  if [[ "${rc}" -ne 0 ]]; then
    success="false"
  fi

  local message="Command completed"
  if [[ "${success}" == "false" ]]; then
    message="Command failed with exit code ${rc}"
  fi

  local args_json
  args_json="$(__integration_result::args_to_json "${cmd[@]}")"

  local json
  json="$(__integration_result::build_json \
    "${success}" "${rc}" "${operation}" "${args_json}" "null" \
    "${stdout_data}" "${stderr_data}" "${message}" \
    "$(__integration_result::iso_timestamp)" "${duration_ms}")"

  __integration_result::emit "${json}"
  return "${rc}"
}

# @description Call a BS function and emit a structured JSON result.
# @description Вызвать функцию BS и вывести структурированный JSON-результат.
# @param $1 Function name / Имя функции
# @param $@ Function arguments / Аргументы функции
# @return exit code of the function / Код возврата функции
# @example
#   result::wrap io::files::copy_file "src.txt" "dst.txt"
result::wrap() {
  local func="${1:-}"
  shift

  if [[ -z "${func}" ]]; then
    result::error "${E_INVALID}" "Function name required"
    return "${E_INVALID}"
  fi

  if ! declare -F -- "${func}" >/dev/null 2>&1; then
    result::error "${E_INVALID}" "Function not found: ${func}"
    return "${E_INVALID}"
  fi

  local start_ms
  start_ms="$(__integration_result::now_ms)"

  local stdout_data
  local stderr_data
  local rc
  __integration_result::capture_wrap stdout_data stderr_data rc "${func}" "$@"

  local end_ms
  local duration_ms
  end_ms="$(__integration_result::now_ms)"
  duration_ms=$((end_ms - start_ms))

  local success="true"
  if [[ "${rc}" -ne 0 ]]; then
    success="false"
  fi

  local message="Function completed"
  if [[ "${success}" == "false" ]]; then
    message="Function failed with exit code ${rc}"
  fi

  local args_json
  args_json="$(__integration_result::args_to_json "$@")"

  local json
  json="$(__integration_result::build_json \
    "${success}" "${rc}" "${func}" "${args_json}" "null" \
    "${stdout_data}" "${stderr_data}" "${message}" \
    "$(__integration_result::iso_timestamp)" "${duration_ms}")"

  __integration_result::emit "${json}"
  return "${rc}"
}

# @description Print a JSON result to stdout.
# @description Вывести JSON-результат в stdout.
# @param $1 JSON string
# @example
#   result::print "$json"
result::print() {
  local json="${1:-}"
  printf '%s\n' "${json}"
}

# @description Write a JSON result to a file.
# @description Записать JSON-результат в файл.
# @param $1 File path / Путь к файлу
# @param $2 JSON string
# @return 0 on success, LIB_ERROR_FILE_OPERATION on failure
result::write() {
  local file="${1:-}"
  local json="${2:-}"

  if [[ -z "${file}" ]]; then
    log::warn "result::write: file path required"
    return "${E_INVALID}"
  fi

  local parent_dir
  parent_dir="$(dirname -- "${file}")"
  if [[ ! -d "${parent_dir}" ]]; then
    if ! mkdir -p -- "${parent_dir}"; then
      log::error "Failed to create directory: ${parent_dir}"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  fi

  if ! printf '%s\n' "${json}" > "${file}"; then
    log::error "Failed to write result to file: ${file}"
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  return "${E_SUCCESS}"
}

# @description Extract a value from a result JSON by key.
# @description Извлечь значение из JSON-результата по ключу.
# @param $1 JSON string
# @param $2 Key / Ключ
# @param $3 Variable name to store value / Имя переменной для значения
# @return 0 on success, LIB_ERROR_DEPENDENCY_MISSING if jq is missing
# @example
#   result::get "$json" "exit_code" rc
result::get() {
  local json="${1:-}"
  local key="${2:-}"
  local var_name="${3:-}"

  if [[ -z "${var_name}" ]]; then
    log::warn "result::get: variable name required"
    return "${E_INVALID}"
  fi

  if ! utils::has jq; then
    log::warn "result::get requires jq"
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
  fi

  local value
  value="$(printf '%s' "${json}" | jq -r ".${key}")"
  printf -v "${var_name}" '%s' "${value}"
  return "${E_SUCCESS}"
}

# @description Check if a result JSON indicates success.
# @description Проверить, что JSON-результат указывает на успех.
# @param $1 JSON string
# @return 0 if success is true, 1 otherwise
# @example
#   if result::is_success "$json"; then ...
result::is_success() {
  local json="${1:-}"

  if utils::has jq; then
    [[ "$(printf '%s' "${json}" | jq -r '.success')" == "true" ]]
  else
    [[ "${json}" == *'"success":true'* ]]
  fi
}
