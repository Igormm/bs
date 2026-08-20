#!/usr/bin/env bash
#
# core/config.sh — Unified configuration loader for BS
# core/config.sh — единый загрузчик конфигурации BS
#
# Loads configuration from defaults, user config, project-local config and
# environment variables. Provides getter/setter API.
#
# Usage / Использование:
#   load "core/config"
#   config::load
#   config::get "BS_LOG_LEVEL" "info"
#   config::set "BS_LOG_LEVEL" "debug"
#
# @depends core/const, core/logger, core/utils

bs::guard "CORE_CONFIG" || return 0

# Зависимости / Dependencies
bs::source_relative "const.sh" "logger.sh" "utils.sh"

# Module version / Версия модуля
declare -g CORE_CONFIG_VERSION="1.0.0"

# Global configuration associative array / Глобальный ассоциативный массив конфигурации
declare -gA BS_CONFIG

# Default configuration file paths / Пути к файлам конфигурации по умолчанию
readonly BS_CONFIG_USER_DIR="${HOME}/.config/bs"
readonly BS_CONFIG_USER_FILE="${BS_CONFIG_USER_DIR}/config.sh"
readonly BS_CONFIG_LOCAL_FILE=".bsrc"

# ==========================================
# Private helpers / Приватные вспомогательные функции
# ==========================================

# @private
# @description Set default values for built-in configuration keys.
# @description Установить значения по умолчанию для встроенных ключей конфигурации.
__config::set_defaults() {
  BS_CONFIG["BS_LOG_LEVEL"]="info"
  BS_CONFIG["BS_SILENT"]="0"
  BS_CONFIG["BS_FRAMEWORK_DRY_RUN"]="false"
  BS_CONFIG["BS_FRAMEWORK_DEBUG"]="false"
  BS_CONFIG["BS_RESULT_FILE"]=""
  BS_CONFIG["BS_FILES_ATOMIC"]="false"
  BS_CONFIG["BS_FILES_BACKUP_SUFFIX"]=""
  BS_CONFIG["BS_FILES_ATOMIC_FALLBACK"]="true"
  BS_CONFIG["BS_LLM_PROVIDER"]=""
  BS_CONFIG["BS_LLM_MODEL"]=""
  BS_CONFIG["BS_LLM_BASE_URL"]=""
  BS_CONFIG["BS_LLM_API_KEY"]=""
}

# @private
# @description Load a configuration file if it exists.
# @description Загрузить файл конфигурации, если он существует.
# @param $1 File path / Путь к файлу
# @return 0 if file loaded or does not exist, 1 on load error
__config::load_file() {
  local file="${1:-}"
  is::not_empty "${file}" && is::file "${file}" || return 0

  log::debug "Loading config file: ${file}"

  local key
  local value
  local line

  while IFS= read -r line || is::not_empty "${line}"; do
    # Skip comments and empty lines / Пропускаем комментарии и пустые строки
    is::empty "${line}" || [[ "${line}" =~ ^[[:space:]]*# ]] && continue

    # Parse KEY="value" or KEY=value / Разбираем KEY="value" или KEY=value
    if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"

      # Remove surrounding quotes / Убираем окружающие кавычки
      if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
        value="${BASH_REMATCH[1]}"
      elif [[ "${value}" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi

      BS_CONFIG["${key}"]="${value}"
    fi
  done < "${file}"

  return 0
}

# @private
# @description Export configuration values to environment variables.
# @description Экспортировать значения конфигурации в переменные окружения.
__config::export_to_env() {
  local key
  for key in "${!BS_CONFIG[@]}"; do
    if is::not_empty "${BS_CONFIG[${key}]:-}"; then
      printf -v "${key}" '%s' "${BS_CONFIG[${key}]}"
      export "${key}"
    fi
  done
}

# ==========================================
# Public API / Публичный API
# ==========================================

# @description Load configuration from all sources.
# @description Загрузить конфигурацию из всех источников.
#   Priority (low → high): defaults, user config, project config, env vars.
#   Приоритет (низкий → высокий): дефолты, пользовательский config, локальный config, env.
# @return 0
# @example
#   config::load
config::load() {
  __config::set_defaults

  # Ensure user config directory exists / Создаём директорию пользовательского конфига
  if ! is::dir "${BS_CONFIG_USER_DIR}"; then
    utils::ignore mkdir -p "${BS_CONFIG_USER_DIR}"
  fi

  # Load user config / Пользовательский конфиг
  __config::load_file "${BS_CONFIG_USER_FILE}"

  # Load project-local config / Локальный конфиг проекта
  if is::file "${BS_CONFIG_LOCAL_FILE}"; then
    __config::load_file "${BS_CONFIG_LOCAL_FILE}"
  fi

  # Environment variables override / Переменные окружения имеют приоритет
  local key
  for key in "${!BS_CONFIG[@]}"; do
    if is::not_empty "${!key:-}"; then
      BS_CONFIG["${key}"]="${!key}"
    fi
  done

  __config::export_to_env

  return "${E_SUCCESS}"
}

# @description Get a configuration value.
# @description Получить значение конфигурации.
# @param $1 Key / Ключ
# @param $2 [optional] Default value / Значение по умолчанию
# @stdout Configuration value / Значение конфигурации
# @return 0 if key exists or default provided, E_INVALID otherwise
# @example
#   config::get "BS_LOG_LEVEL" "info"
config::get() {
  local key="${1:-}"
  local default_value="${2:-}"

  if is::empty "${key}"; then
    log::warn "config::get: key required"
    return "${E_INVALID}"
  fi

  if [[ -v "BS_CONFIG[${key}]" ]]; then
    printf '%s' "${BS_CONFIG[${key}]}"
  elif is::not_empty "${default_value}"; then
    printf '%s' "${default_value}"
  else
    return "${E_INVALID}"
  fi

  return "${E_SUCCESS}"
}

# @description Set a configuration value at runtime.
# @description Установить значение конфигурации в runtime.
# @param $1 Key / Ключ
# @param $2 Value / Значение
# @return 0 on success, E_INVALID on missing key
# @example
#   config::set "BS_LOG_LEVEL" "debug"
config::set() {
  local key="${1:-}"
  local value="${2:-}"

  if is::empty "${key}"; then
    log::warn "config::set: key required"
    return "${E_INVALID}"
  fi

  BS_CONFIG["${key}"]="${value}"
  printf -v "${key}" '%s' "${value}"
  export "${key}"

  return "${E_SUCCESS}"
}

# @description List all configured keys and values.
# @description Вывести все настроенные ключи и значения.
# @stdout key=value pairs, one per line
# @example
#   config::list
config::list() {
  local key
  printf '%s\n' "${!BS_CONFIG[@]}" | sort | while IFS= read -r key; do
    printf '%s=%s\n' "${key}" "${BS_CONFIG[${key}]}"
  done
}

# @description Return path to user config file.
# @description Вернуть путь к пользовательскому файлу конфигурации.
# @stdout Path / Путь
config::user_file() {
  printf '%s' "${BS_CONFIG_USER_FILE}"
}

# @description Return path to project-local config file.
# @description Вернуть путь к локальному файлу конфигурации проекта.
# @stdout Path / Путь
config::local_file() {
  printf '%s' "${BS_CONFIG_LOCAL_FILE}"
}
