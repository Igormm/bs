#!/usr/bin/env bash

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
# Uninstall / Удаление:
#   sudo ./install.sh uninstall
#   ./install.sh --local uninstall
#
# PATH helpers (local only) / Настройка PATH (только для --local):
#   ./install.sh --local --path         # print snippet / вывести сниппет
#   ./install.sh --local --update-path  # auto add to ~/.bashrc and/or ~/.zshrc / авто-добавление
#
# Overrides (optional) / Переопределения (опционально):
#   PREFIX=... BIN_DIR=... LIB_DIR=...

set -euo pipefail

# 1. Проверка bash
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
  printf 'ERROR: bash 4.0+ required\n' >&2
  exit 1
fi

# 2. Run the modular installer
INSTALLER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/install"
source "${INSTALLER_DIR}/main.sh" "$@"