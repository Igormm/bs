#!/usr/bin/env bash

# Environment checking functions for the installer

# Загрузить утилиты если они еще не загружены
if [[ -z "${__UTILS_SOURCED:-}" ]]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/../core/utils.sh"
fi

# Check if already installed
checks::is_already_installed() {
  [[ -d "${TARGET_LIB}" && -f "${TARGET_BIN}" ]]
}
