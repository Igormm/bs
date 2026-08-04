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
# Important / Важно:
#   The installer COPIES files to the target location. After installation
#   the source repository can be removed. Target paths depend on mode:
#     system (default): /usr/local/lib/bs  + /usr/local/bin/bs
#     local  (--local): ~/.local/lib/bs    + ~/.local/bin/bs
#     custom:           $LIB_DIR/bs        + $BIN_DIR/bs
#
# Overrides (optional) / Переопределения (опционально):
#   PREFIX=... BIN_DIR=... LIB_DIR=...
#

# Определить каталог запуска скрипта
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Определить каталог с файлами установки
INSTALLER_DIR="${SCRIPT_DIR}/install"

# Проверить каталог с core модулями
if [[ ! -d "${SCRIPT_DIR}/core" ]]; then
  printf 'ERROR: core modules directory not found: %s\n' "${SCRIPT_DIR}/core" >&2
  exit 1
fi

# Проверить файл утилит
if [[ ! -f "${SCRIPT_DIR}/core/utils.sh" ]]; then
  printf 'ERROR: Core utilites not found: %s\n' "${SCRIPT_DIR}/core/utils.sh" >&2
  exit 1
fi

# modules sourcing
# Подключить Utils как можно раньше
if ! source -- "${SCRIPT_DIR}/core/utils.sh"; then
  printf 'ERROR: failed to source file: %s\n' "${SCRIPT_DIR}/core/utils.sh" >&2
  exit 1
fi

# Использовать строгий режим (как только функция доступна)
utils::strict

# Проверить файл утилит
if [[ ! -f "${SCRIPT_DIR}/core/const.sh" ]]; then
  printf 'ERROR: Core module const not found: %s\n' "${SCRIPT_DIR}/core/const.sh" >&2
  exit 1
fi

# Проверить файл утилит
if [[ ! -f "${SCRIPT_DIR}/core/errorhandler.sh" ]]; then
  printf 'ERROR: Core module error handler not found: %s\n' "${SCRIPT_DIR}/core/errorhandler.sh" >&2
  exit 1
fi

# Проверить файл утилит
if [[ ! -f "${SCRIPT_DIR}/core/logger.sh" ]]; then
  printf 'ERROR: Core module logger not found: %s\n' "${SCRIPT_DIR}/core/logger.sh" >&2
  exit 1
fi

# Проверить файл утилит
if [[ ! -f "${SCRIPT_DIR}/core/version.sh" ]]; then
  printf 'ERROR: Core module version not found: %s\n' "${SCRIPT_DIR}/core/version.sh" >&2
  exit 1
fi

# Проверить каталог с bootstrap
if [[ ! -d "${SCRIPT_DIR}/bootstrap" ]]; then
  printf 'ERROR: bootstrap modules directory not found: %s\n' "${SCRIPT_DIR}/bootstrap" >&2
  exit 1
fi

# Проверить файлы необходимые для самозагрузки
if [[ ! -f "${SCRIPT_DIR}/bootstrap/init.sh" ]]; then
  printf 'ERROR: bootstrap init utilites not found: %s\n' "${SCRIPT_DIR}/bootstrap/init.sh" >&2
  exit 1
fi

# Проверить файлы необходимые для самозагрузки
if [[ ! -f "${SCRIPT_DIR}/bootstrap/loader.sh" ]]; then
  printf 'ERROR: bootstrap loader utilites not found: %s\n' "${SCRIPT_DIR}/bootstrap/loader.sh" >&2
  exit 1
fi

# Проверить каталог с модулями для инсталяции 
if [[ ! -d "${INSTALLER_DIR}" ]]; then
  printf 'ERROR: installation directory not found: %s\n' "${INSTALLER_DIR}" >&2
  exit 1
fi

# Проверить файл инсталятор 
if [[ ! -f "${INSTALLER_DIR}/main.sh" ]]; then
  printf 'ERROR: installation file main.sh not found: %s\n' "${INSTALLER_DIR}/main.sh" >&2
  exit 1
fi

# Проверить файл инсталятор
if [[ ! -f "${INSTALLER_DIR}/actions.sh" ]]; then
  printf 'ERROR: installation file actions.sh not found: %s\n' "${INSTALLER_DIR}/actions.sh" >&2
  exit 1
fi

# Проверить файл инсталятор
if [[ ! -f "${INSTALLER_DIR}/checks.sh" ]]; then
  printf 'ERROR: installation file checks.sh not found: %s\n' "${INSTALLER_DIR}/checks.sh" >&2
  exit 1
fi

# Проверить файл инсталятор
if [[ ! -f "${INSTALLER_DIR}/path_manager.sh" ]]; then
  printf 'ERROR: installation file path_manager.sh not found: %s\n' "${INSTALLER_DIR}/path_manager.sh" >&2
  exit 1
fi

# Проверить добавление Actions
if ! source -- "${INSTALLER_DIR}/actions.sh"; then
  printf 'ERROR: failed to source file: %s\n' "${INSTALLER_DIR}/actions.sh" >&2
  exit 1
fi

# Проверить функцию utils::strict 
if ! declare -F -- "utils::strict" >/dev/null 2>&1; then
  printf 'ERROR: required function %q not defined\n' "utils::strict" >&2
  exit 1
fi

# Проверить функцию utils::ensure_shell_version
if ! declare -F -- "utils::ensure_shell_version" >/dev/null 2>&1; then
  printf 'ERROR: required function %q not defined\n' "utils::ensure_shell_version" >&2
  exit 1
fi

# Проверка версии bash\zsh
utils::ensure_shell_version

# Run the modular installer / Запустить модуль инсталяции 
source "${INSTALLER_DIR}/main.sh" "$@"
