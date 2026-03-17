#!/usr/bin/env bash
#
# BS installer (Linux) / Установщик BS (Linux)
#
# Modes / Режимы:
#   1) System install (requires sudo/root) / Системная установка (нужен sudo/root):
#        sudo ./install.sh
#        sudo ./install.sh install
#   2) Local install in ~/.local (no sudo) / Локальная установка в ~/.local (без sudo):
#        ./install.sh --local
#        ./install.sh --local install
#
# Uninstall / Удаление
#   sudo ./install.sh uninstall
#   ./install.sh --local uninstall
#
# PATH helpers (local only) / Настройка PATH (только для --local):
#   ./install.sh --local --path         # print snippet / вывести сниппет
#   ./install.sh --local --update-path  # auto add to ~/.bashrc and/or ~/.zshrc / авто-добавление
#
# Overrides (optional) / Переопределения (опционально):
#   PREFIX=... BIN_DIR=... LIB_DIR=...
#

# Определить каталог запуска скрипта
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Определил каталог установки
INSTALLER_DIR="${SCRIPT_DIR}/install"

# Проверить каталог с core модулями
if [[ ! -d "${SCRIPT_DIR}/core" ]]; then
  printf 'ERROR: core for modules directory not found: %s\n' "${SCRIPT_DIR}/core/utils.sh" >&2
  exit 1
fi

# Проверить каталог с модулями для инсталяции 
if [[ ! -d "${INSTALLER_DIR}" ]]; then
  printf 'ERROR: installation directory not found: %s\n' "${INSTALLER_DIR}" >&2
  exit 1
fi

# Проверить файл инсталятор 
if [[ ! -f "${INSTALLER_DIR}/main.sh" ]]; then
  printf 'ERROR: installation core directory not found: %s\n' "${INSTALLER_DIR}/main.sh" >&2
  exit 1
fi

# Проверить каталог core модулей
if [[ ! -d "${SCRIPT_DIR}/core" ]]; then
  printf 'ERROR: Core utilites not found: %s\n' "${SCRIPT_DIR}/core" >&2
  exit 1
fi

# Проверить файл утилит
if [[ ! -f "${SCRIPT_DIR}/core/utils.sh" ]]; then
  printf 'ERROR: Core utilites not found: %s\n' "${SCRIPT_DIR}/core/utils.sh" >&2
  exit 1
fi

# Использовать строгий режим
set -euo pipefail
IFS=$'\n\t'

# Загрузить утилиты
source "${SCRIPT_DIR}/core/utils.sh"

# Проверка версии bash\zsh
utils::ensure_shell_version 4

# Run the modular installer / Запустить модуль инсталяции 
source "${INSTALLER_DIR}/main.sh" "$@"