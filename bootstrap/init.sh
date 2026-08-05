#!/usr/bin/env bash
#
# Bs bootstrap initializer / Инициализатор бутстрапа BS
# Purpose: detect project root, export BS_ROOT, and load core via loader.
# Назначение: определить корень проекта, экспортировать BS_ROOT и загрузить ядро через loader.
#

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа,
# этот файл подключается через source и не должен менять настройки чужого shell
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points;
# this file is sourced and must not change the caller's shell settings

# @description Show usage help. This file must be sourced.
usage() {
  cat <<'HELP'
BS bootstrap init

Usage:
  source /path/to/bootstrap/init.sh
  или: source "$BS_ROOT/bootstrap/init.sh"

Notes:
  - Must be sourced, not executed, to affect current shell.
  - Должен вызываться через source, чтобы повлиять на текущую оболочку.
HELP
}

# If executed directly, warn and exit. We only support bash/zsh.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'ERROR: This script must be sourced, not executed.\n' >&2
  usage
  exit 1
fi

# Idempotency: skip if already initialized
if [[ -n "${BS_INITIALIZED:-}" ]]; then
  # Best-effort debug if logger is available
  command -v log::debug >/dev/null 2>&1 && log::debug 'BS already initialized, skipping'
  return 0
fi

# Resolve BS_ROOT once
if [[ -n "${BS_ROOT:-}" && -d "${BS_ROOT}" ]]; then
  :
else
  readonly __BS_INIT_DIR__="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
  readonly __BS_ROOT_CANDIDATE__="$(cd -- "${__BS_INIT_DIR__}/.." >/dev/null 2>&1 && pwd -P)"
  if [[ -d "${__BS_ROOT_CANDIDATE__}" && -f "${__BS_ROOT_CANDIDATE__}/bs" ]]; then
    export BS_ROOT="${__BS_ROOT_CANDIDATE__}"
  else
    printf 'ERROR: Unable to determine BS_ROOT. Set BS_ROOT environment variable.\n' >&2
    return 1
  fi
fi

# Minimal PATH tweak for local installs
append_local_bin_to_path() {
  local -r needle="${HOME}/.local/bin"
  case ":${PATH}:" in
    *":${needle}:"*) return 0 ;;
    *) export PATH="${needle}:${PATH}" ;;
  esac
}

# Add local bin to PATH
append_local_bin_to_path

# BS_HOME: историческое расхождение с BS_ROOT в lib-модулях
# BS_HOME: historical mismatch with BS_ROOT in lib modules
: "${BS_HOME:=${BS_ROOT}}"
export BS_HOME

# Load loader
if [[ -f "${BS_ROOT}/bootstrap/loader.sh" ]]; then
  # shellcheck disable=SC1090
  source "${BS_ROOT}/bootstrap/loader.sh"
elif [[ -f "${BS_ROOT}/loader.sh" ]]; then
  # shellcheck disable=SC1090
  source "${BS_ROOT}/loader.sh"
else
  printf 'BS: error: loader.sh not found in %s/bootstrap/ or %s/\n' "${BS_ROOT}" "${BS_ROOT}" >&2
  return 1
fi

# Load core modules via loader
# core/prereq must come first: it provides bs::guard and bs::source_relative
load "core/prereq"
load "core/const"
load "core/logger"
load "core/errorhandler"
load "core/version"
load "core/utils"
load "core/config"
load "core/deps"

# Load configuration from files and env
config::load

# Mark as initialized
export BS_INITIALIZED=1

# Optional info
if [[ "${BS_SILENT:-0}" != 1 ]]; then
  printf 'BS bootstrap initialized from: %s\n' "${BS_ROOT}"
fi