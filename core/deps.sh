#!/usr/bin/env bash
#
# core/deps.sh — Dependency checker for BS modules
# core/deps.sh — проверка зависимостей для модулей BS
#
# Provides a unified way to check external commands required by modules.
# Modules declare optional dependencies via the @optdeps annotation.
#
# Usage / Использование:
#   load "core/deps"
#   deps::has jq
#   deps::require curl "curl is required for HTTP requests"
#   deps::list_missing "lib/integration/http"
#
# @depends core/const, core/logger, core/utils

# Core prerequisites
source "$(dirname -- "${BASH_SOURCE[0]}")/prereq.sh"
bs::guard "CORE_DEPS" || return 0

# Зависимости / Dependencies
bs::source_relative "const.sh" "logger.sh" "utils.sh"

# Module version / Версия модуля
declare -g CORE_DEPS_VERSION="1.0.0"

# ==========================================
# Private helpers / Приватные вспомогательные функции
# ==========================================

# @private
# @description Parse optional dependencies from module header.
# @description Разобрать опциональные зависимости из заголовка модуля.
# @param $1 Module path relative to BS_ROOT / Путь модуля относительно BS_ROOT
# @stdout Space-separated list of commands / Список команд через пробел
__deps::parse_optdeps() {
  local module_path="${1:-}"
  local module_file="${BS_ROOT}/${module_path}.sh"

  if [[ -z "${module_path}" || ! -f "${module_file}" ]]; then
    return 0
  fi

  local line
  line=$(grep -m1 "^[[:space:]]*#.*@optdeps" "${module_file}" 2>/dev/null || true)

  if [[ -z "${line}" ]]; then
    return 0
  fi

  echo "${line}" | sed 's/.*@optdeps[[:space:]]*//; s/[[:space:]]*$//; s/,[[:space:]]*/ /g; s/[[:space:]]\+/ /g'
}

# ==========================================
# Public API / Публичный API
# ==========================================

# @description Check if a command is available with diagnostic logging.
# @description Проверить наличие команды с диагностическим логом.
# @param $1 Command name / Имя команды
# @return 0 if available, 1 otherwise / 0 если доступна
# @example
#   if deps::has jq; then ...
deps::has() {
  local cmd="${1:-}"

  if [[ -z "${cmd}" ]]; then
    log::warn "deps::has: command name required"
    return 1
  fi

  if utils::has "${cmd}"; then
    log::debug "Dependency available: ${cmd}"
    return 0
  fi

  log::debug "Dependency missing: ${cmd}"
  return 1
}

# @description Require a command to be available; error if missing.
# @description Требовать наличие команды; ошибка, если её нет.
# @param $1 Command name / Имя команды
# @param $2 [optional] Error message / Сообщение об ошибке
# @return 0 if available, INTEGRATION_ERROR_MISSING_DEPS otherwise
# @example
#   deps::require curl "HTTP module requires curl"
deps::require() {
  local cmd="${1:-}"
  local message="${2:-}"

  if [[ -z "${cmd}" ]]; then
    log::warn "deps::require: command name required"
    return "${E_INVALID}"
  fi

  if deps::has "${cmd}"; then
    return 0
  fi

  if [[ -n "${message}" ]]; then
    log::error "${message}"
  else
    log::error "Required dependency not found: ${cmd}"
  fi

  return "${INTEGRATION_ERROR_MISSING_DEPS}"
}

# @description List missing optional dependencies for a module.
# @description Список недостающих опциональных зависимостей модуля.
# @param $1 Module path / Путь модуля
# @stdout Space-separated list of missing commands / Список недостающих команд
# @return 0 if all available, 1 if any missing
# @example
#   missing=$(deps::list_missing "lib/integration/http")
deps::list_missing() {
  local module_path="${1:-}"

  if [[ -z "${module_path}" ]]; then
    log::warn "deps::list_missing: module path required"
    return "${E_INVALID}"
  fi

  local optdeps
  optdeps="$(__deps::parse_optdeps "${module_path}")"

  if [[ -z "${optdeps}" ]]; then
    return 0
  fi

  local -a deps=()
  utils::split deps "${optdeps}" " "

  local missing=()
  local cmd
  for cmd in "${deps[@]}"; do
    if ! utils::has "${cmd}"; then
      missing+=("${cmd}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '%s\n' "${missing[*]}"
    return 1
  fi

  return 0
}

# @description Check if all optional dependencies for a module are available.
# @description Проверить, что все опциональные зависимости модуля доступны.
# @param $1 Module path / Путь модуля
# @return 0 if all available, 1 otherwise
# @example
#   deps::check_module "lib/integration/llm"
deps::check_module() {
  local module_path="${1:-}"

  if [[ -z "${module_path}" ]]; then
    log::warn "deps::check_module: module path required"
    return "${E_INVALID}"
  fi

  local missing
  missing="$(deps::list_missing "${module_path}" 2>/dev/null || true)"

  if [[ -n "${missing}" ]]; then
    log::warn "Module ${module_path} is missing optional dependencies: ${missing}"
    return 1
  fi

  log::debug "Module ${module_path} dependencies satisfied"
  return 0
}
