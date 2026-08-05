#!/usr/bin/env bash
#
# lib/integration/http.sh — HTTP client for BS
# lib/integration/http.sh — HTTP-клиент для BS
#
# Simple curl/wget-based HTTP client with dry-run support, timeouts and retries.
#
# Usage / Использование:
#   load "lib/integration/http"
#   http::get "https://api.example.com/status"
#   http::post "https://api.example.com/users" '{"name":"alice"}' --header "Content-Type: application/json"
#   http::download "https://example.com/file.iso" "/tmp/file.iso"
#   http::retry 3 1 http::get "https://api.example.com/status"
#
# @depends core/const, core/logger, core/utils
# @optdeps curl, wget

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "IO_INTEGRATION_HTTP" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# Module version / Версия модуля
declare -g IO_INTEGRATION_HTTP_VERSION="1.0.0"

# ==========================================
# Private helpers / Приватные вспомогательные функции
# ==========================================

# @private
# @description Detect available HTTP backend (curl or wget).
# @description Определить доступный HTTP-бэкенд (curl или wget).
# @stdout "curl" or "wget"
# @return 0 if backend found, INTEGRATION_ERROR_MISSING_DEPS otherwise
__http::backend() {
  if utils::has curl; then
    printf '%s' "curl"
    return 0
  fi
  if utils::has wget; then
    printf '%s' "wget"
    return 0
  fi
  return "${INTEGRATION_ERROR_MISSING_DEPS}"
}

# @private
# @description Build curl command arguments from options.
# @description Собрать аргументы для curl из опций.
# @param $1 method
# @param $2 url
# @param $@ options (--header, --timeout, --data, --silent)
# @stdout command arguments
__http::curl_args() {
  local method="${1:-GET}"
  local url="${2:-}"
  shift 2

  local -a args=("-s" "-L" "-w" "\n%{http_code}")
  args+=("-X" "${method}")

  local opt
  while [[ $# -gt 0 ]]; do
    opt="${1}"
    case "${opt}" in
      --header)
        args+=("-H" "${2}")
        shift 2
        ;;
      --data)
        args+=("-d" "${2}")
        shift 2
        ;;
      --timeout)
        args+=("--max-time" "${2}")
        shift 2
        ;;
      --silent)
        shift
        ;;
      *)
        log::warn "Unknown http option: ${opt}"
        shift
        ;;
    esac
  done

  args+=("--" "${url}")
  printf '%s\n' "${args[@]}"
}

# @private
# @description Execute curl request, return body and status.
# @description Выполнить curl-запрос, вернуть тело и статус.
# @param $1 method
# @param $2 url
# @param $@ options
# @stdout HTTP status code / HTTP-статус
# @return 0 on HTTP 2xx, INTEGRATION_ERROR_HTTP otherwise
__http::curl_request() {
  local method="${1:-GET}"
  local url="${2:-}"
  shift 2

  local -a args=()
  while IFS= read -r line; do
    args+=("${line}")
  done < <(__http::curl_args "${method}" "${url}" "$@")

  local tmpfile
  tmpfile="$(mktemp)"

  local rc=0
  curl "${args[@]}" >"${tmpfile}" 2>/dev/null || rc=$?

  local output
  output="$(cat "${tmpfile}")"
  rm -f -- "${tmpfile}"

  local status
  status="${output##*$'\n'}"
  local body="${output%$'\n'*}"

  # Print body to stdout / Выводим тело в stdout
  printf '%s' "${body}"

  if [[ "${rc}" -ne 0 ]]; then
    return "${INTEGRATION_ERROR_HTTP}"
  fi

  if [[ "${status}" =~ ^2 ]]; then
    return 0
  fi

  return "${INTEGRATION_ERROR_HTTP}"
}

# @private
# @description Execute wget request, return body.
# @description Выполнить wget-запрос, вернуть тело.
# @param $1 method
# @param $2 url
# @param $@ options
# @return 0 on success, INTEGRATION_ERROR_HTTP otherwise
__http::wget_request() {
  local method="${1:-GET}"
  local url="${2:-}"
  shift 2

  local -a args=("-q" "-O" "-")

  local opt
  while [[ $# -gt 0 ]]; do
    opt="${1}"
    case "${opt}" in
      --header)
        args+=("--header=${2}")
        shift 2
        ;;
      --data)
        args+=("--post-data=${2}")
        shift 2
        ;;
      --timeout)
        args+=("--timeout=${2}")
        shift 2
        ;;
      --silent)
        shift
        ;;
      *)
        log::warn "Unknown http option: ${opt}"
        shift
        ;;
    esac
  done

  if [[ "${method}" != "GET" && "${method}" != "POST" ]]; then
    log::warn "wget backend only supports GET and POST, got: ${method}"
  fi

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] wget ${args[*]} ${url}"
    return "${E_SUCCESS}"
  fi

  wget "${args[@]}" -- "${url}" || return "${INTEGRATION_ERROR_HTTP}"
}

# ==========================================
# Public API / Публичный API
# ==========================================

# @description Perform an HTTP request.
# @description Выполнить HTTP-запрос.
# @param $1 HTTP method / HTTP-метод
# @param $2 URL / Адрес
# @param $@ Options: --header, --data, --timeout, --silent / Опции
# @return 0 on HTTP 2xx (curl) or success (wget), INTEGRATION_ERROR_HTTP otherwise
# @example
#   http::request GET "https://api.example.com/status"
#   http::request POST "https://api.example.com/users" --data '{"name":"alice"}' --header "Content-Type: application/json"
http::request() {
  local method="${1:-}"
  local url="${2:-}"
  shift 2

  if [[ -z "${method}" || -z "${url}" ]]; then
    log::warn "http::request: method and URL required"
    return "${E_INVALID}"
  fi

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] ${method} ${url}"
    return "${E_SUCCESS}"
  fi

  local backend
  backend="$(__http::backend)"
  if [[ -z "${backend}" ]]; then
    log::error "No HTTP backend available (curl or wget required)"
    return "${INTEGRATION_ERROR_MISSING_DEPS}"
  fi

  log::debug "HTTP ${method} ${url} (backend: ${backend})"

  case "${backend}" in
    curl)
      __http::curl_request "${method}" "${url}" "$@"
      ;;
    wget)
      __http::wget_request "${method}" "${url}" "$@"
      ;;
    *)
      return "${INTEGRATION_ERROR_HTTP}"
      ;;
  esac
}

# @description Perform an HTTP GET request.
# @description Выполнить HTTP GET-запрос.
# @param $1 URL / Адрес
# @param $@ Options / Опции
# @return 0 on success, error code otherwise
# @example
#   http::get "https://api.example.com/status"
http::get() {
  local url="${1:-}"
  shift
  http::request "GET" "${url}" "$@"
}

# @description Perform an HTTP POST request.
# @description Выполнить HTTP POST-запрос.
# @param $1 URL / Адрес
# @param $2 Request body / Тело запроса
# @param $@ Options / Опции
# @return 0 on success, error code otherwise
# @example
#   http::post "https://api.example.com/users" '{"name":"alice"}' --header "Content-Type: application/json"
http::post() {
  local url="${1:-}"
  local data="${2:-}"
  shift 2
  http::request "POST" "${url}" --data "${data}" "$@"
}

# @description Download a file via HTTP.
# @description Скачать файл по HTTP.
# @param $1 URL / Адрес
# @param $2 Destination file / Файл назначения
# @param $@ Options / Опции
# @return 0 on success, error code otherwise
# @example
#   http::download "https://example.com/file.iso" "/tmp/file.iso" --timeout 60
http::download() {
  local url="${1:-}"
  local file="${2:-}"
  shift 2

  if [[ -z "${url}" || -z "${file}" ]]; then
    log::warn "http::download: URL and destination file required"
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

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] download ${url} -> ${file}"
    return "${E_SUCCESS}"
  fi

  local backend
  backend="$(__http::backend)"
  if [[ -z "${backend}" ]]; then
    log::error "No HTTP backend available (curl or wget required)"
    return "${INTEGRATION_ERROR_MISSING_DEPS}"
  fi

  log::info "Downloading: ${url} -> ${file}"

  if [[ "${backend}" == "curl" ]]; then
    local -a args=("-L" "-s" "-o" "${file}")
    local opt
    while [[ $# -gt 0 ]]; do
      opt="${1}"
      case "${opt}" in
        --timeout)
          args+=("--max-time" "${2}")
          shift 2
          ;;
        --header)
          args+=("-H" "${2}")
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    curl "${args[@]}" -- "${url}" || return "${INTEGRATION_ERROR_HTTP}"
  else
    wget -q -O "${file}" -- "${url}" || return "${INTEGRATION_ERROR_HTTP}"
  fi

  return "${E_SUCCESS}"
}

# @description Retry a command with exponential or fixed backoff.
# @description Повторить команду с фиксированной или экспоненциальной задержкой.
# @param $1 Number of attempts / Количество попыток
# @param $2 Delay in seconds between attempts / Задержка в секундах
# @param $@ Command to retry / Команда для повтора
# @return exit code of the last attempt / Код возврата последней попытки
# @example
#   http::retry 3 1 http::get "https://api.example.com/status"
http::retry() {
  local attempts="${1:-1}"
  local delay="${2:-1}"
  shift 2

  if [[ -z "${attempts}" || -z "${delay}" || $# -eq 0 ]]; then
    log::warn "http::retry: attempts, delay and command required"
    return "${E_INVALID}"
  fi

  local i
  local rc=0
  for ((i=1; i<=attempts; i++)); do
    "$@" && return 0
    rc=$?
    log::warn "Attempt ${i}/${attempts} failed, waiting ${delay}s..."
    if [[ "${i}" -lt "${attempts}" ]]; then
      sleep "${delay}"
    fi
  done

  return "${rc}"
}
