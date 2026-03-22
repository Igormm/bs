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
printf "INFO: script dir: ${SCRIPT_DIR}\n"

# Определить каталог с файлами установки
INSTALLER_DIR="${SCRIPT_DIR}/install"
printf "INFO: installer dir: ${INSTALLER_DIR}\n"

# Проверить каталог с core модулями
if [[ ! -d "${SCRIPT_DIR}/core" ]]; then
  printf 'ERROR: core modules directory not found: %s\n' "${SCRIPT_DIR}/core" >&2
  return 1
fi

# Проверить файл утилит
if [[ ! -f "${SCRIPT_DIR}/core/utils.sh" ]]; then
  printf 'ERROR: Core utilites not found: %s\n' "${SCRIPT_DIR}/core/utils.sh" >&2
  return 1
fi

# Проверить файл с константами
if [[ ! -f "${SCRIPT_DIR}/core/const.sh" ]]; then
  printf 'ERROR: Core module const not found: %s\n' "${SCRIPT_DIR}/core/const.sh" >&2
  return 1
fi

# Проверить помошник с методами вывода
if [[ ! -f "${SCRIPT_DIR}/core/helper.sh" ]]; then
  printf 'ERROR: Core module helper not found: %s\n' "${SCRIPT_DIR}/core/helper.sh" >&2
  return 1
fi

# Проверить файл обработчик ошибок
if [[ ! -f "${SCRIPT_DIR}/core/errorhandler.sh" ]]; then
  printf 'ERROR: Core module error handler not found: %s\n' "${SCRIPT_DIR}/core/errorhandler.sh" >&2
  return 1
fi

# Проверить файл с методами логирования
if [[ ! -f "${SCRIPT_DIR}/core/logger.sh" ]]; then
  printf 'ERROR: Core module logger not found: %s\n' "${SCRIPT_DIR}/core/logger.sh" >&2
  return 1
fi

# Проверить файл с методами контроля версий
if [[ ! -f "${SCRIPT_DIR}/core/version.sh" ]]; then
  printf 'ERROR: Core Version module not found: %s\n' "${SCRIPT_DIR}/core/version.sh" >&2
  return 1
fi

# Проверить каталог с bootstrap (самозагрузки)
if [[ ! -d "${SCRIPT_DIR}/bootstrap" ]]; then
  printf 'ERROR: bootstrap modules directory not found: %s\n' "${SCRIPT_DIR}/bootstrap" >&2
  return 1
fi

# Проверить файлы необходимые для самозагрузки
if [[ ! -f "${SCRIPT_DIR}/bootstrap/init.sh" ]]; then
  printf 'ERROR: file bootstrap init utilites not found: %s\n' "${SCRIPT_DIR}/bootstrap/init.sh" >&2
  return 1
fi

# Проверить файлы необходимые для самозагрузки
if [[ ! -f "${SCRIPT_DIR}/bootstrap/loader.sh" ]]; then
  printf 'ERROR: bootstrap loader utilites not found: %s\n' "${SCRIPT_DIR}/bootstrap/loader.sh" >&2
  return 1
fi

# Проверить каталог с модулями для инсталяции
if [[ ! -d "${INSTALLER_DIR}" ]]; then
  printf 'ERROR: installation directory not found: %s\n' "${INSTALLER_DIR}" >&2
  return 1
fi

# Проверить файл инсталятор
if [[ ! -f "${INSTALLER_DIR}/main.sh" ]]; then
  printf 'ERROR: installation file main.sh not found: %s\n' "${INSTALLER_DIR}/main.sh" >&2
  return 1
fi

# Проверить файл инсталятор
if [[ ! -f "${INSTALLER_DIR}/actions.sh" ]]; then
  printf 'ERROR: installation file action.sh not found: %s\n' "${INSTALLER_DIR}/action.sh" >&2
  return 1
fi

# Проверить файл инсталятор
if [[ ! -f "${INSTALLER_DIR}/checks.sh" ]]; then
  printf 'ERROR: installation file checks.sh not found: %s\n' "${INSTALLER_DIR}/checks.sh" >&2
  return 1
fi

# Проверить файл инсталятор
if [[ ! -f "${INSTALLER_DIR}/pathmanager.sh" ]]; then
  printf 'ERROR: installation file pathmanager.sh not found: %s\n' "${INSTALLER_DIR}/pathmanager.sh" >&2
  return 1
fi

# modules sourcing
source core/utils.sh
source install/actions.sh

# Использовать строгий режим
utils::strict

# Проверка версии bash\zsh
utils::ensure_shell_version 4

# Run the modular installer / Запустить модуль инсталяции
source "${INSTALLER_DIR}/main.sh" "$@"
