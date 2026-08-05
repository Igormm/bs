#!/usr/bin/env bash
#
# lib/integration/llm.sh — LLM client for BS
# lib/integration/llm.sh — LLM-клиент для BS
#
# Unified interface for OpenAI-compatible and Ollama local models.
# Returns structured JSON responses suitable for parsing by Go backends,
# CI pipelines and web interfaces.
#
# Usage / Использование:
#   load "lib/integration/llm"
#
#   export OPENAI_API_KEY="sk-..."
#   llm::chat openai gpt-3.5-turbo "Hello"
#
#   export OLLAMA_HOST="http://localhost:11434"
#   llm::chat ollama llama3 "Explain bash arrays"
#
# @depends core/const, core/logger, core/utils, lib/integration/result
# @optdeps jq

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/prereq.sh"
bs::guard "IO_INTEGRATION_LLM" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "result.sh"

# Module version / Версия модуля
declare -g IO_INTEGRATION_LLM_VERSION="1.0.0"

# Default configuration / Конфигурация по умолчанию
: "${LLM_OPENAI_URL:=https://api.openai.com/v1/chat/completions}"
: "${LLM_OPENAI_MODEL:=gpt-3.5-turbo}"
: "${LLM_OLLAMA_HOST:=http://localhost:11434}"
: "${LLM_OLLAMA_MODEL:=llama3}"
: "${LLM_TIMEOUT:=60}"

# ==========================================
# Private helpers / Приватные вспомогательные функции
# ==========================================

# @private
# @description Validate provider name.
# @description Проверить имя провайдера.
# @param $1 provider
# @return 0 if supported, E_INVALID otherwise
__llm::validate_provider() {
  local provider="${1:-}"

  case "${provider}" in
    openai|ollama)
      return 0
      ;;
    *)
      log::warn "Unsupported LLM provider: ${provider}"
      return "${E_INVALID}"
      ;;
  esac
}

# @private
# @description Build JSON request body for OpenAI.
# @description Собрать тело JSON-запроса для OpenAI.
# @param $1 model
# @param $2 message
# @stdout JSON body
__llm::openai_body() {
  local model="${1:-}"
  local message="${2:-}"

  local escaped_message
  escaped_message="$(__llm::json_escape "${message}")"

  printf '{"model":"%s","messages":[{"role":"user","content":"%s"}]}' \
    "$(__llm::json_escape "${model}")" \
    "${escaped_message}"
}

# @private
# @description Build JSON request body for Ollama.
# @description Собрать тело JSON-запроса для Ollama.
# @param $1 model
# @param $2 message
# @stdout JSON body
__llm::ollama_body() {
  local model="${1:-}"
  local message="${2:-}"

  local escaped_message
  escaped_message="$(__llm::json_escape "${message}")"

  printf '{"model":"%s","messages":[{"role":"user","content":"%s"}],"stream":false}' \
    "$(__llm::json_escape "${model}")" \
    "${escaped_message}"
}

# @private
# @description Minimal JSON string escape.
# @description Минимальное экранирование строки для JSON.
# @param $1 raw string
# @stdout escaped string
__llm::json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "${s}"
}

# @private
# @description Extract a value from JSON using jq or simple grep fallback.
# @description Извлечь значение из JSON через jq или простой fallback.
# @param $1 JSON string
# @param $2 jq query
# @stdout value (raw)
__llm::json_query() {
  local json="${1:-}"
  local query="${2:-}"

  if utils::has jq; then
    printf '%s' "${json}" | jq -r "${query}"
    return 0
  fi

  # Fallback for .choices[0].message.content (OpenAI)
  if [[ "${query}" == ".choices[0].message.content" ]]; then
    __llm::fallback_extract "${json}" "content"
    return 0
  fi

  # Fallback for .message.content (Ollama)
  if [[ "${query}" == ".message.content" ]]; then
    __llm::fallback_extract "${json}" "content"
    return 0
  fi

  printf ''
  return 0
}

# @private
# @description Simple grep-based extractor for "content":"..." fields.
# @description Простой grep-экстрактор для полей "content":"...".
# @param $1 JSON string
# @param $2 field name
# @stdout extracted value
__llm::fallback_extract() {
  local json="${1:-}"
  local field="${2:-}"

  local value
  value="$(printf '%s' "${json}" | grep -oP "\"${field}\"\\s*:\\s*\"\\K([^\"\\\\]|\\\\.)*" | head -n1)"

  # Unescape common sequences
  value="${value//\\n/$'\n'}"
  value="${value//\\t/$'\t'}"
  value="${value//\\\"/\"}"
  value="${value//\\\\/\\}"

  printf '%s' "${value}"
}

# @private
# @description Perform the HTTP request for an LLM provider.
# @description Выполнить HTTP-запрос для LLM-провайдера.
# @param $1 provider
# @param $2 request body
# @stdout response body
# @return 0 on success, INTEGRATION_ERROR_LLM otherwise
__llm::request() {
  local provider="${1:-}"
  local body="${2:-}"
  local api_key="${3:-}"

  local url
  local -a headers=()

  case "${provider}" in
    openai)
      url="${LLM_OPENAI_URL}"
      headers+=("Content-Type: application/json")
      if [[ -n "${api_key}" ]]; then
        headers+=("Authorization: Bearer ${api_key}")
      fi
      ;;
    ollama)
      url="${LLM_OLLAMA_HOST}/api/chat"
      headers+=("Content-Type: application/json")
      ;;
    *)
      log::error "Unknown LLM provider: ${provider}"
      return "${INTEGRATION_ERROR_LLM}"
      ;;
  esac

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] LLM ${provider} request to ${url}"
    printf '{"dry_run":true,"provider":"%s"}' "${provider}"
    return 0
  fi

  local response
  local rc=0

  # Build curl args manually to support multiple headers
  local -a curl_args=(-s -L -m "${LLM_TIMEOUT}" -X POST)
  local header
  for header in "${headers[@]}"; do
    curl_args+=(-H "${header}")
  done
  curl_args+=(-d "${body}" -- "${url}")

  response="$(curl "${curl_args[@]}" 2>/dev/null)" || rc=$?

  if [[ "${rc}" -ne 0 ]]; then
    log::error "LLM request failed (curl exit ${rc})"
    return "${INTEGRATION_ERROR_LLM}"
  fi

  printf '%s' "${response}"
  return 0
}

# ==========================================
# Public API / Публичный API
# ==========================================

# @description List supported LLM providers.
# @description Список поддерживаемых LLM-провайдеров.
# @stdout space-separated provider names
# @return 0
# @example
#   llm::providers
llm::providers() {
  printf '%s' "openai ollama"
  return 0
}

# @description Check if a provider is configured/available.
# @description Проверить, настроен ли провайдер и доступен ли он.
# @param $1 provider (optional, default: env LLM_PROVIDER or "openai")
# @return 0 if available, 1 otherwise
# @example
#   if llm::is_available openai; then ...
llm::is_available() {
  local provider="${1:-${LLM_PROVIDER:-openai}}"

  if ! __llm::validate_provider "${provider}" >/dev/null 2>&1; then
    return 1
  fi

  case "${provider}" in
    openai)
      [[ -n "${OPENAI_API_KEY:-}" ]] || [[ -n "${LLM_OPENAI_API_KEY:-}" ]]
      return
      ;;
    ollama)
      local host
      host="${LLM_OLLAMA_HOST}"
      if utils::has curl; then
        curl -s -m 2 "${host}/api/tags" >/dev/null 2>&1
        return
      fi
      if utils::has wget; then
        wget -q -T 2 -O - "${host}/api/tags" >/dev/null 2>&1
        return
      fi
      return 1
      ;;
  esac

  return 1
}

# @description Send a chat message to an LLM provider.
# @description Отправить сообщение в LLM-провайдер.
# @param $1 provider (openai|ollama)
# @param $2 model name
# @param $3 message
# @return 0 on success, error code otherwise
# @stdout response content
# @example
#   llm::chat openai gpt-3.5-turbo "Hello"
#   llm::chat ollama llama3 "Explain arrays"
llm::chat() {
  local provider="${1:-}"
  local model="${2:-}"
  local message="${3:-}"

  if [[ -z "${provider}" || -z "${model}" || -z "${message}" ]]; then
    log::warn "llm::chat: provider, model and message required"
    return "${E_INVALID}"
  fi

  if ! __llm::validate_provider "${provider}"; then
    return "${E_INVALID}"
  fi

  local api_key=""
  if [[ "${provider}" == "openai" ]]; then
    api_key="${OPENAI_API_KEY:-${LLM_OPENAI_API_KEY:-}}"
    if [[ -z "${api_key}" && "${FRAMEWORK_DRY_RUN:-false}" != "true" ]]; then
      log::error "OpenAI API key not set (OPENAI_API_KEY or LLM_OPENAI_API_KEY)"
      return "${INTEGRATION_ERROR_LLM}"
    fi
  fi

  local body
  case "${provider}" in
    openai)
      body="$(__llm::openai_body "${model}" "${message}")"
      ;;
    ollama)
      body="$(__llm::ollama_body "${model}" "${message}")"
      ;;
  esac

  local response
  local rc=0
  response="$(__llm::request "${provider}" "${body}" "${api_key}")" || rc=$?

  if [[ "${rc}" -ne 0 ]]; then
    return "${rc}"
  fi

  if [[ -z "${response}" ]]; then
    log::error "LLM returned empty response"
    return "${INTEGRATION_ERROR_LLM}"
  fi

  # In dry-run mode return the stub response as-is.
  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    printf '%s' "${response}"
    return 0
  fi

  local content
  case "${provider}" in
    openai)
      content="$(__llm::json_query "${response}" ".choices[0].message.content")"
      ;;
    ollama)
      content="$(__llm::json_query "${response}" ".message.content")"
      ;;
  esac

  if [[ -z "${content}" ]]; then
    log::warn "LLM response did not contain expected content"
    printf '%s' "${response}"
    return "${INTEGRATION_ERROR_LLM}"
  fi

  printf '%s' "${content}"
  return 0
}

# @description Send a file's contents as a chat message.
# @description Отправить содержимое файла в качестве сообщения.
# @param $1 provider
# @param $2 model
# @param $3 file path
# @return 0 on success, error code otherwise
# @stdout response content
# @example
#   llm::chat_file openai gpt-3.5-turbo /tmp/code.sh
llm::chat_file() {
  local provider="${1:-}"
  local model="${2:-}"
  local file="${3:-}"

  if [[ -z "${file}" ]]; then
    log::warn "llm::chat_file: file path required"
    return "${E_INVALID}"
  fi

  if [[ ! -f "${file}" ]]; then
    log::error "File not found: ${file}"
    return "${LIB_ERROR_FILE_NOT_FOUND}"
  fi

  local content
  content="$(cat -- "${file}")"

  llm::chat "${provider}" "${model}" "${content}"
}

# @description Return a structured JSON result for an LLM chat.
# @description Вернуть структурированный JSON-результат для чата с LLM.
# @param $1 provider
# @param $2 model
# @param $3 message
# @stdout JSON result object
# @return exit code
# @example
#   llm::result openai gpt-3.5-turbo "Hello"
llm::result() {
  local provider="${1:-}"
  local model="${2:-}"
  local message="${3:-}"

  if ! load "lib/integration/result" 2>/dev/null; then
    log::error "llm::result requires lib/integration/result"
    return "${INTEGRATION_ERROR_MISSING_DEPS}"
  fi

  local content
  local rc=0
  content="$(llm::chat "${provider}" "${model}" "${message}" 2>/dev/null)" || rc=$?

  if [[ "${rc}" -ne 0 ]]; then
    result::error "${rc}" "LLM chat failed"
    return "${rc}"
  fi

  result::ok "${content}" "LLM response received"
}
