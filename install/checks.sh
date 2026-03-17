#!/usr/bin/env bash

# Environment checking functions for the installer

# Загрузить утилиты если они еще не загружены
if [[ -z "${__UTILS_SOURCED:-}" ]]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/../core/utils.sh"
fi

# Check if already installed
is_already_installed() {
  [[ -d "${TARGET_LIB}" && -f "${TARGET_BIN}" ]]
}

# Check shell environment
check_shell_environment() {
  # Use the utility function instead of duplicating code
  utils::ensure_shell_version 4
}