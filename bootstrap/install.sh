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
#
# Safe shell options / Безопасные опции оболочки:
#   -e: exit on error / выход при ошибке
#   -u: error on undefined variables / ошибка при неопределённых переменных
#   -o pipefail: pipeline fails on any command error / ошибка пайплайна при падении любой команды
set -euo pipefail

# Require Bash explicitly (uses Bash-isms) / Явно требуем bash (используются особенности bash)
check_shell_environment() {
  if [[ -z "${BASH_VERSION:-}" ]]; then
    printf "ERROR: This installer requires bash.\n" >&2
    printf "Установщик требует bash. Запустите: bash ./install.sh\n" >&2
    exit 1
  fi
}
check_shell_environment

# Help message / Справка
usage() {
  cat <<'HELP'
BS installer

Usage:
  ./install.sh [--local] [install|uninstall] [--path|--update-path]
  sudo ./install.sh [install|uninstall]

Notes:
  --path and --update-path are valid only with --local.
  --path и --update-path работают только с --local.

Examples:
  sudo ./install.sh
  sudo ./install.sh install
  sudo ./install.sh uninstall

  ./install.sh --local
  ./install.sh --local install
  ./install.sh --local uninstall

  ./install.sh --local --path
  ./install.sh --local --update-path
HELP
}

# Ask user to confirm / Подтверждение действия
confirm() {
  local prompt="$1"
  local ans
  read -r -p "${prompt} [y/N]: " ans
  [[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

# Parse arguments / Парсинг аргументов
MODE="system"        # system|local
ACTION="install"     # install|uninstall
FLAG_PATH="0"        # 0|1
FLAG_UPDATE_PATH="0" # 0|1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      MODE="local"; shift ;;
    --path)
      FLAG_PATH="1"; shift ;;
    --update-path)
      FLAG_UPDATE_PATH="1"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    install|uninstall|remove)
      ACTION="$1"; shift ;;
    *)
      printf "ERROR: Неизвестный аргумент: %s (см. --help)\n" "$1" >&2
      exit 1 ;;
  esac
done

# Alias: remove -> uninstall / Синоним: remove -> uninstall
if [[ "${ACTION}" == "remove" ]]; then
  ACTION="uninstall"
fi

# Resolve paths / Определение путей
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(dirname "${SCRIPT_DIR}")"

# Choose PREFIX based on mode / Выбор PREFIX по режиму
if [[ "${MODE}" == "local" ]]; then
  : "${PREFIX:="$HOME/.local"}"   # ~/.local by default / по умолчанию ~/.local
else
  : "${PREFIX:=/usr/local}"       # /usr/local by default / по умолчанию /usr/local
fi

# Derive BIN_DIR and LIB_DIR / Определяем BIN_DIR и LIB_DIR
: "${BIN_DIR:="${PREFIX}/bin"}"
: "${LIB_DIR:="${PREFIX}/lib"}"

# Final install locations / Финальные пути установки
TARGET_LIB="${LIB_DIR}/bs"  # BS libraries root / корень библиотек BS
TARGET_BIN="${BIN_DIR}/bs"  # wrapper executable / враппер-скрипт

# Check if already installed / Проверка, установлено ли уже
is_already_installed() {
  [[ -d "${TARGET_LIB}" && -f "${TARGET_BIN}" ]]
}

# PATH snippet (local) / Сниппет PATH (локально)
path_snippet() {
  cat <<'SNIP'
# BS (local) - add to PATH / добавить в PATH
export PATH="$HOME/.local/bin:$PATH"
SNIP
}

# Print PATH hint / Подсказка по PATH
print_path_hint() {
  printf "To use shebang: #!/usr/bin/env bs\n"
  printf "Чтобы работало: #!/usr/bin/env bs\n"
  printf "Add ~/.local/bin to PATH (e.g., in ~/.bashrc or ~/.zshrc):\n"
  printf "Добавьте ~/.local/bin в PATH (например, в ~/.bashrc или ~/.zshrc):\n\n"
  path_snippet
  printf "\n"
}

# Update ~/.bashrc with PATH line (with confirmation) / Добавление PATH в ~/.bashrc (с подтверждением)
update_path_bashrc() {
  local bashrc="${HOME}/.bashrc"
  local line='export PATH="$HOME/.local/bin:$PATH"'

  [[ -f "${bashrc}" ]] || touch "${bashrc}"

  if grep -Fqx "${line}" "${bashrc}"; then
    printf "PATH уже настроен в %s\n" "${bashrc}"
    return 0
  fi

  if confirm "Добавить PATH в ${bashrc}?"; then
    printf "\n%s\n" "${line}" >> "${bashrc}"
    printf "Добавлено. Применить: source ~/.bashrc\n"
  else
    printf "Пропущено.\n"
  fi
}

# Auto add PATH to bash/zsh (idempotent) / Авто-добавление PATH в bash/zsh (идемпотентно)
auto_update_path() {
  local bashrc="${HOME}/.bashrc"
  local zshrc="${HOME}/.zshrc"
  local line='export PATH="$HOME/.local/bin:$PATH"'

  # bashrc
  if [[ -f "${bashrc}" || ! -f "${zshrc}" ]]; then
    if ! grep -Fqx "${line}" "${bashrc}" 2>/dev/null; then
      printf "\n%s\n" "${line}" >> "${bashrc}"
      printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${bashrc}"
    else
      printf "PATH уже настроен в %s\n" "${bashrc}"
    fi
  fi

  # zshrc
  if [[ -f "${zshrc}" ]]; then
    if ! grep -Fqx "${line}" "${zshrc}" 2>/dev/null; then
      printf "\n%s\n" "${line}" >> "${zshrc}"
      printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${zshrc}"
    else
      printf "PATH уже настроен в %s\n" "${zshrc}"
    fi
  fi
}

# Install / Установка
do_install() {
  # Root required for system mode / Для системной установки нужен root
  if [[ "${MODE}" == "system" ]]; then
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      printf "ERROR: Нужны права root. Запустите: sudo ./install.sh\n" >&2
      exit 1
    fi
  fi

  if is_already_installed; then
    printf "Предупреждение: BS уже установлена в %s\n" "${TARGET_LIB}"
    printf "Удалите сначала старую версию: ./install.sh %s uninstall\n" "${MODE:+--$MODE}"
    printf "Или используйте переопределения: PREFIX=... BIN_DIR=... LIB_DIR=...\n"
    exit 1
  fi

  printf "Установка BS (%s)\n" "${MODE}"
  printf "  SOURCE_ROOT: %s\n" "${SOURCE_ROOT}"
  printf "  PREFIX:      %s\n" "${PREFIX}"
  printf "  TARGET_LIB:  %s\n" "${TARGET_LIB}"
  printf "  TARGET_BIN:  %s\n" "${TARGET_BIN}"

  # Ensure dirs / Создаём каталоги
  mkdir -p "${BIN_DIR}"
  mkdir -p "${LIB_DIR}"

  # Clean target lib / Очистка целевой директории библиотек
  rm -rf "${TARGET_LIB}"
  mkdir -p "${TARGET_LIB}"

  # Copy payload / Копируем полезные файлы
  cp -a "${SOURCE_ROOT}/bootstrap" "${TARGET_LIB}/"
  cp -a "${SOURCE_ROOT}/core"      "${TARGET_LIB}/"
  cp -a "${SOURCE_ROOT}/bs"        "${TARGET_LIB}/"   # main launcher / основной исполняемый файл
  cp -a "${SOURCE_ROOT}/lib"       "${TARGET_LIB}/"

  # Create wrapper / Создаём враппер
  if [[ "${MODE}" == "local" ]]; then
    cat >"${TARGET_BIN}" <<'WRAP'
#!/usr/bin/env bash
export BS_ROOT="$HOME/.local/lib/bs"
exec "$BS_ROOT/bs" "$@"
WRAP
  else
    cat >"${TARGET_BIN}" <<'WRAP'
#!/usr/bin/env bash
export BS_ROOT="/usr/local/lib/bs"
exec "$BS_ROOT/bs" "$@"
WRAP
  fi
  chmod 0755 "${TARGET_BIN}"

  printf "Готово.\n"

  # For local installs, auto update PATH / Для локальной установки — автообновление PATH
  if [[ "${MODE}" == "local" ]]; then
    auto_update_path
  fi
}

# Uninstall / Удаление
do_uninstall() {
  # Root required for system mode / Для системного удаления нужен root
  if [[ "${MODE}" == "system" ]]; then
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      printf "ERROR: Нужны права root. Запустите: sudo ./install.sh\n" >&2
      exit 1
    fi
  fi

  printf "Удаление BS (%s)\n" "${MODE}"
  printf "  TARGET_BIN: %s\n" "${TARGET_BIN}"
  printf "  TARGET_LIB: %s\n" "${TARGET_LIB}"

  # Remove wrapper / Удаляем враппер
  if [[ -f "${TARGET_BIN}" ]]; then
    rm -f "${TARGET_BIN}"
    printf "Удален: %s\n" "${TARGET_BIN}"
  else
    printf "Нет файла: %s\n" "${TARGET_BIN}"
  fi

  # Remove libs / Удаляем библиотеки
  if [[ -d "${TARGET_LIB}" ]]; then
    rm -rf "${TARGET_LIB}"
    printf "Удален: %s\n" "${TARGET_LIB}"
  else
    printf "Нет каталога: %s\n" "${TARGET_LIB}"
  fi

  # Do NOT wipe user's ~/.local trees; only tidy empty parents / НЕ очищаем весь ~/.local; только пробуем удалить пустые родительские каталоги
  if [[ "${MODE}" == "local" ]]; then
    # Attempt to remove empty BIN_DIR / Попытка удалить пустой BIN_DIR
    if [[ -d "${BIN_DIR}" ]] && rmdir "${BIN_DIR}" 2>/dev/null; then
      printf "Удален пустой каталог: %s\n" "${BIN_DIR}"
    fi
    # Attempt to remove empty LIB_DIR / Попытка удалить пустой LIB_DIR
    if [[ -d "${LIB_DIR}" ]] && rmdir "${LIB_DIR}" 2>/dev/null; then
      printf "Удален пустой каталог: %s\n" "${LIB_DIR}"
    fi
  fi

  printf "Готово.\n"
}

# PATH flags (local only) / Обработка флагов PATH (только для локального режима)
if [[ "${MODE}" == "local" && "${FLAG_PATH}" == "1" ]]; then
  print_path_hint
  exit 0
fi

if [[ "${MODE}" == "local" && "${FLAG_UPDATE_PATH}" == "1" ]]; then
  auto_update_path
  exit 0
fi

# Execute action / Выполнение действия
case "${ACTION}" in
  install)
    do_install ;;
  uninstall)
    do_uninstall ;;
  *)
    printf "ERROR: Неизвестное действие: %s\n" "${ACTION}" >&2
    exit 1 ;;
esac#!/usr/bin/env bash
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
#
# Safe shell options / Безопасные опции оболочки:
#   -e: exit on error / выход при ошибке
#   -u: error on undefined variables / ошибка при неопределённых переменных
#   -o pipefail: pipeline fails on any command error / ошибка пайплайна при падении любой команды
set -euo pipefail

# Require Bash explicitly (uses Bash-isms) / Явно требуем bash (используются особенности bash)
if [[ -z "${BASH_VERSION:-}" ]]; then
  printf "ERROR: This installer requires bash.\n" >&2
  printf "Установщик требует bash. Запустите: bash ./install.sh\n" >&2
  exit 1
fi

# Help message / Справка
usage() {
  cat <<'HELP'
BS installer

Usage:
  ./install.sh [--local] [install|uninstall] [--path|--update-path]
  sudo ./install.sh [install|uninstall]

Notes:
  --path and --update-path are valid only with --local.
  --path и --update-path работают только с --local.

Examples:
  sudo ./install.sh
  sudo ./install.sh install
  sudo ./install.sh uninstall

  ./install.sh --local
  ./install.sh --local install
  ./install.sh --local uninstall

  ./install.sh --local --path
  ./install.sh --local --update-path
HELP
}

# Ask user to confirm / Подтверждение действия
confirm() {
  local prompt="$1"
  local ans
  read -r -p "${prompt} [y/N]: " ans
  [[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

# Parse arguments / Парсинг аргументов
MODE="system"        # system|local
ACTION="install"     # install|uninstall
FLAG_PATH="0"        # 0|1
FLAG_UPDATE_PATH="0" # 0|1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      MODE="local"; shift ;;
    --path)
      FLAG_PATH="1"; shift ;;
    --update-path)
      FLAG_UPDATE_PATH="1"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    install|uninstall|remove)
      ACTION="$1"; shift ;;
    *)
      printf "ERROR: Неизвестный аргумент: %s (см. --help)\n" "$1" >&2
      exit 1 ;;
  esac
done

# Alias: remove -> uninstall / Синоним: remove -> uninstall
if [[ "${ACTION}" == "remove" ]]; then
  ACTION="uninstall"
fi

# Resolve paths / Определение путей
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(dirname "${SCRIPT_DIR}")"

# Choose PREFIX based on mode / Выбор PREFIX по режиму
if [[ "${MODE}" == "local" ]]; then
  : "${PREFIX:="$HOME/.local"}"   # ~/.local by default / по умолчанию ~/.local
else
  : "${PREFIX:=/usr/local}"       # /usr/local by default / по умолчанию /usr/local
fi

# Derive BIN_DIR and LIB_DIR / Определяем BIN_DIR и LIB_DIR
: "${BIN_DIR:="${PREFIX}/bin"}"
: "${LIB_DIR:="${PREFIX}/lib"}"

# Final install locations / Финальные пути установки
TARGET_LIB="${LIB_DIR}/bs"  # BS libraries root / корень библиотек BS
TARGET_BIN="${BIN_DIR}/bs"  # wrapper executable / враппер-скрипт

# Check if already installed / Проверка, установлено ли уже
is_already_installed() {
  [[ -d "${TARGET_LIB}" && -f "${TARGET_BIN}" ]]
}

# PATH snippet (local) / Сниппет PATH (локально)
path_snippet() {
  cat <<'SNIP'
# BS (local) - add to PATH / добавить в PATH
export PATH="$HOME/.local/bin:$PATH"
SNIP
}

# Print PATH hint / Подсказка по PATH
print_path_hint() {
  printf "To use shebang: #!/usr/bin/env bs\n"
  printf "Чтобы работало: #!/usr/bin/env bs\n"
  printf "Add ~/.local/bin to PATH (e.g., in ~/.bashrc or ~/.zshrc):\n"
  printf "Добавьте ~/.local/bin в PATH (например, в ~/.bashrc или ~/.zshrc):\n\n"
  path_snippet
  printf "\n"
}

# Update ~/.bashrc with PATH line (with confirmation) / Добавление PATH в ~/.bashrc (с подтверждением)
update_path_bashrc() {
  local bashrc="${HOME}/.bashrc"
  local line='export PATH="$HOME/.local/bin:$PATH"'

  [[ -f "${bashrc}" ]] || touch "${bashrc}"

  if grep -Fqx "${line}" "${bashrc}"; then
    printf "PATH уже настроен в %s\n" "${bashrc}"
    return 0
  fi

  if confirm "Добавить PATH в ${bashrc}?"; then
    printf "\n%s\n" "${line}" >> "${bashrc}"
    printf "Добавлено. Применить: source ~/.bashrc\n"
  else
    printf "Пропущено.\n"
  fi
}

# Auto add PATH to bash/zsh (idempotent) / Авто-добавление PATH в bash/zsh (идемпотентно)
auto_update_path() {
  local bashrc="${HOME}/.bashrc"
  local zshrc="${HOME}/.zshrc"
  local line='export PATH="$HOME/.local/bin:$PATH"'

  # bashrc
  if [[ -f "${bashrc}" || ! -f "${zshrc}" ]]; then
    if ! grep -Fqx "${line}" "${bashrc}" 2>/dev/null; then
      printf "\n%s\n" "${line}" >> "${bashrc}"
      printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${bashrc}"
    else
      printf "PATH уже настроен в %s\n" "${bashrc}"
    fi
  fi

  # zshrc
  if [[ -f "${zshrc}" ]]; then
    if ! grep -Fqx "${line}" "${zshrc}" 2>/dev/null; then
      printf "\n%s\n" "${line}" >> "${zshrc}"
      printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${zshrc}"
    else
      printf "PATH уже настроен в %s\n" "${zshrc}"
    fi
  fi
}

# Install / Установка
do_install() {
  # Root required for system mode / Для системной установки нужен root
  if [[ "${MODE}" == "system" ]]; then
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      printf "ERROR: Нужны права root. Запустите: sudo ./install.sh\n" >&2
      exit 1
    fi
  fi

  if is_already_installed; then
    printf "Предупреждение: BS уже установлена в %s\n" "${TARGET_LIB}"
    printf "Удалите сначала старую версию: ./install.sh %s uninstall\n" "${MODE:+--$MODE}"
    printf "Или используйте переопределения: PREFIX=... BIN_DIR=... LIB_DIR=...\n"
    exit 1
  fi

  printf "Установка BS (%s)\n" "${MODE}"
  printf "  SOURCE_ROOT: %s\n" "${SOURCE_ROOT}"
  printf "  PREFIX:      %s\n" "${PREFIX}"
  printf "  TARGET_LIB:  %s\n" "${TARGET_LIB}"
  printf "  TARGET_BIN:  %s\n" "${TARGET_BIN}"

  # Ensure dirs / Создаём каталоги
  mkdir -p "${BIN_DIR}"
  mkdir -p "${LIB_DIR}"

  # Clean target lib / Очистка целевой директории библиотек
  rm -rf "${TARGET_LIB}"
  mkdir -p "${TARGET_LIB}"

  # Copy payload / Копируем полезные файлы
  cp -a "${SOURCE_ROOT}/bootstrap" "${TARGET_LIB}/"
  cp -a "${SOURCE_ROOT}/core"      "${TARGET_LIB}/"
  cp -a "${SOURCE_ROOT}/bs"        "${TARGET_LIB}/"   # main launcher / основной исполняемый файл
  cp -a "${SOURCE_ROOT}/lib"       "${TARGET_LIB}/"

  # Create wrapper / Создаём враппер
  if [[ "${MODE}" == "local" ]]; then
    cat >"${TARGET_BIN}" <<'WRAP'
#!/usr/bin/env bash
export BS_ROOT="$HOME/.local/lib/bs"
exec "$BS_ROOT/bs" "$@"
WRAP
  else
    cat >"${TARGET_BIN}" <<'WRAP'
#!/usr/bin/env bash
export BS_ROOT="/usr/local/lib/bs"
exec "$BS_ROOT/bs" "$@"
WRAP
  fi
  chmod 0755 "${TARGET_BIN}"

  printf "Готово.\n"

  # For local installs, auto update PATH / Для локальной установки — автообновление PATH
  if [[ "${MODE}" == "local" ]]; then
    auto_update_path
  fi
}

# Uninstall / Удаление
do_uninstall() {
  # Root required for system mode / Для системного удаления нужен root
  if [[ "${MODE}" == "system" ]]; then
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      printf "ERROR: Нужны права root. Запустите: sudo ./install.sh\n" >&2
      exit 1
    fi
  fi

  printf "Удаление BS (%s)\n" "${MODE}"
  printf "  TARGET_BIN: %s\n" "${TARGET_BIN}"
  printf "  TARGET_LIB: %s\n" "${TARGET_LIB}"

  # Remove wrapper / Удаляем враппер
  if [[ -f "${TARGET_BIN}" ]]; then
    rm -f "${TARGET_BIN}"
    printf "Удален: %s\n" "${TARGET_BIN}"
  else
    printf "Нет файла: %s\n" "${TARGET_BIN}"
  fi

  # Remove libs / Удаляем библиотеки
  if [[ -d "${TARGET_LIB}" ]]; then
    rm -rf "${TARGET_LIB}"
    printf "Удален: %s\n" "${TARGET_LIB}"
  else
    printf "Нет каталога: %s\n" "${TARGET_LIB}"
  fi

  # Do NOT wipe user's ~/.local trees; only tidy empty parents / НЕ очищаем весь ~/.local; только пробуем удалить пустые родительские каталоги
  if [[ "${MODE}" == "local" ]]; then
    # Attempt to remove empty BIN_DIR / Попытка удалить пустой BIN_DIR
    if [[ -d "${BIN_DIR}" ]] && rmdir "${BIN_DIR}" 2>/dev/null; then
      printf "Удален пустой каталог: %s\n" "${BIN_DIR}"
    fi
    # Attempt to remove empty LIB_DIR / Попытка удалить пустой LIB_DIR
    if [[ -d "${LIB_DIR}" ]] && rmdir "${LIB_DIR}" 2>/dev/null; then
      printf "Удален пустой каталог: %s\n" "${LIB_DIR}"
    fi
  fi

  printf "Готово.\n"
}

# PATH flags (local only) / Обработка флагов PATH (только для локального режима)
if [[ "${MODE}" == "local" && "${FLAG_PATH}" == "1" ]]; then
  print_path_hint
  exit 0
fi

if [[ "${MODE}" == "local" && "${FLAG_UPDATE_PATH}" == "1" ]]; then
  auto_update_path
  exit 0
fi

# Execute action / Выполнение действия
case "${ACTION}" in
  install)
    do_install ;;
  uninstall)
    do_uninstall ;;
  *)
    printf "ERROR: Неизвестное действие: %s\n" "${ACTION}" >&2
    exit 1 ;;
esac#!/usr/bin/env bash

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
#
# Safe shell options / Безопасные опции оболочки:
#   -e: exit on error / выход при ошибке
#   -u: error on undefined variables / ошибка при неопределённых переменных
#   -o pipefail: pipeline fails on any command error / ошибка пайплайна при падении любой команды
set -euo pipefail

# Require Bash explicitly (uses Bash-isms) / Явно требуем bash (используются особенности bash)
if [[ -z "${BASH_VERSION:-}" ]]; then
  printf "ERROR: This installer requires bash.\n" >&2
  printf "Установщик требует bash. Запустите: bash ./install.sh\n" >&2
  exit 1
fi

# Help message / Справка
usage() {
  cat <<'HELP'
BS installer

Usage:
  ./install.sh [--local] [install|uninstall] [--path|--update-path]
  sudo ./install.sh [install|uninstall]

Notes:
  --path and --update-path are valid only with --local.
  --path и --update-path работают только с --local.

Examples:
  sudo ./install.sh
  sudo ./install.sh install
  sudo ./install.sh uninstall

  ./install.sh --local
  ./install.sh --local install
  ./install.sh --local uninstall

  ./install.sh --local --path
  ./install.sh --local --update-path
HELP
}

# Ask user to confirm / Подтверждение действия
confirm() {
  local prompt="$1"
  local ans
  read -r -p "${prompt} [y/N]: " ans
  [[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

# Parse arguments / Парсинг аргументов
MODE="system"        # system|local
ACTION="install"     # install|uninstall
FLAG_PATH="0"        # 0|1
FLAG_UPDATE_PATH="0" # 0|1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      MODE="local"; shift ;;
    --path)
      FLAG_PATH="1"; shift ;;
    --update-path)
      FLAG_UPDATE_PATH="1"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    install|uninstall|remove)
      ACTION="$1"; shift ;;
    *)
      printf "ERROR: Неизвестный аргумент: %s (см. --help)\n" "$1" >&2
      exit 1 ;;
  esac
done

# Alias: remove -> uninstall / Синоним: remove -> uninstall
if [[ "${ACTION}" == "remove" ]]; then
  ACTION="uninstall"
fi

# Resolve paths / Определение путей
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(dirname "${SCRIPT_DIR}")"

# Choose PREFIX based on mode / Выбор PREFIX по режиму
if [[ "${MODE}" == "local" ]]; then
  : "${PREFIX:="$HOME/.local"}"   # ~/.local by default / по умолчанию ~/.local
else
  : "${PREFIX:=/usr/local}"       # /usr/local by default / по умолчанию /usr/local
fi

# Derive BIN_DIR and LIB_DIR / Определяем BIN_DIR и LIB_DIR
: "${BIN_DIR:="${PREFIX}/bin"}"
: "${LIB_DIR:="${PREFIX}/lib"}"

# Final install locations / Финальные пути установки
TARGET_LIB="${LIB_DIR}/bs"  # BS libraries root / корень библиотек BS
TARGET_BIN="${BIN_DIR}/bs"  # wrapper executable / враппер-скрипт

# Check if already installed / Проверка, установлено ли уже
is_already_installed() {
  [[ -d "${TARGET_LIB}" && -f "${TARGET_BIN}" ]]
}

# PATH snippet (local) / Сниппет PATH (локально)
path_snippet() {
  cat <<'SNIP'
# BS (local) - add to PATH / добавить в PATH
export PATH="$HOME/.local/bin:$PATH"
SNIP
}

# Print PATH hint / Подсказка по PATH
print_path_hint() {
  printf "To use shebang: #!/usr/bin/env bs\n"
  printf "Чтобы работало: #!/usr/bin/env bs\n"
  printf "Add ~/.local/bin to PATH (e.g., in ~/.bashrc or ~/.zshrc):\n"
  printf "Добавьте ~/.local/bin в PATH (например, в ~/.bashrc или ~/.zshrc):\n\n"
  path_snippet
  printf "\n"
}

# Update ~/.bashrc with PATH line (with confirmation) / Добавление PATH в ~/.bashrc (с подтверждением)
update_path_bashrc() {
  local bashrc="${HOME}/.bashrc"
  local line='export PATH="$HOME/.local/bin:$PATH"'

  [[ -f "${bashrc}" ]] || touch "${bashrc}"

  if grep -Fqx "${line}" "${bashrc}"; then
    printf "PATH уже настроен в %s\n" "${bashrc}"
    return 0
  fi

  if confirm "Добавить PATH в ${bashrc}?"; then
    printf "\n%s\n" "${line}" >> "${bashrc}"
    printf "Добавлено. Применить: source ~/.bashrc\n"
  else
    printf "Пропущено.\n"
  fi
}

# Auto add PATH to bash/zsh (idempotent) / Авто-добавление PATH в bash/zsh (идемпотентно)
auto_update_path() {
  local bashrc="${HOME}/.bashrc"
  local zshrc="${HOME}/.zshrc"
  local line='export PATH="$HOME/.local/bin:$PATH"'

  # bashrc
  if [[ -f "${bashrc}" || ! -f "${zshrc}" ]]; then
    if ! grep -Fqx "${line}" "${bashrc}" 2>/dev/null; then
      printf "\n%s\n" "${line}" >> "${bashrc}"
      printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${bashrc}"
    else
      printf "PATH уже настроен в %s\n" "${bashrc}"
    fi
  fi

  # zshrc
  if [[ -f "${zshrc}" ]]; then
    if ! grep -Fqx "${line}" "${zshrc}" 2>/dev/null; then
      printf "\n%s\n" "${line}" >> "${zshrc}"
      printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${zshrc}"
    else
      printf "PATH уже настроен в %s\n" "${zshrc}"
    fi
  fi
}

# Install / Установка
do_install() {
  # Root required for system mode / Для системной установки нужен root
  if [[ "${MODE}" == "system" ]]; then
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      printf "ERROR: Нужны права root. Запустите: sudo ./install.sh\n" >&2
      exit 1
    fi
  fi

  if is_already_installed; then
    printf "Предупреждение: BS уже установлена в %s\n" "${TARGET_LIB}"
    printf "Удалите сначала старую версию: ./install.sh %s uninstall\n" "${MODE:+--$MODE}"
    printf "Или используйте переопределения: PREFIX=... BIN_DIR=... LIB_DIR=...\n"
    exit 1
  fi

  printf "Установка BS (%s)\n" "${MODE}"
  printf "  SOURCE_ROOT: %s\n" "${SOURCE_ROOT}"
  printf "  PREFIX:      %s\n" "${PREFIX}"
  printf "  TARGET_LIB:  %s\n" "${TARGET_LIB}"
  printf "  TARGET_BIN:  %s\n" "${TARGET_BIN}"

  # Ensure dirs / Создаём каталоги
  mkdir -p "${BIN_DIR}"
  mkdir -p "${LIB_DIR}"

  # Clean target lib / Очистка целевой директории библиотек
  rm -rf "${TARGET_LIB}"
  mkdir -p "${TARGET_LIB}"

  # Copy payload / Копируем полезные файлы
  cp -a "${SOURCE_ROOT}/bootstrap" "${TARGET_LIB}/"
  cp -a "${SOURCE_ROOT}/core"      "${TARGET_LIB}/"
  cp -a "${SOURCE_ROOT}/bs"        "${TARGET_LIB}/"   # main launcher / основной исполняемый файл
  cp -a "${SOURCE_ROOT}/lib"       "${TARGET_LIB}/"

  # Create wrapper / Создаём враппер
  if [[ "${MODE}" == "local" ]]; then
    cat >"${TARGET_BIN}" <<'WRAP'
#!/usr/bin/env bash
export BS_ROOT="$HOME/.local/lib/bs"
exec "$BS_ROOT/bs" "$@"
WRAP
  else
    cat >"${TARGET_BIN}" <<'WRAP'
#!/usr/bin/env bash
export BS_ROOT="/usr/local/lib/bs"
exec "$BS_ROOT/bs" "$@"
WRAP
  fi
  chmod 0755 "${TARGET_BIN}"

  printf "Готово.\n"

  # For local installs, auto update PATH / Для локальной установки — автообновление PATH
  if [[ "${MODE}" == "local" ]]; then
    auto_update_path
  fi
}

# Uninstall / Удаление
do_uninstall() {
  # Root required for system mode / Для системного удаления нужен root
  if [[ "${MODE}" == "system" ]]; then
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      printf "ERROR: Нужны права root. Запустите: sudo ./install.sh\n" >&2
      exit 1
    fi
  fi

  printf "Удаление BS (%s)\n" "${MODE}"
  printf "  TARGET_BIN: %s\n" "${TARGET_BIN}"
  printf "  TARGET_LIB: %s\n" "${TARGET_LIB}"

  # Remove wrapper / Удаляем враппер
  if [[ -f "${TARGET_BIN}" ]]; then
    rm -f "${TARGET_BIN}"
    printf "Удален: %s\n" "${TARGET_BIN}"
  else
    printf "Нет файла: %s\n" "${TARGET_BIN}"
  fi

  # Remove libs / Удаляем библиотеки
  if [[ -d "${TARGET_LIB}" ]]; then
    rm -rf "${TARGET_LIB}"
    printf "Удален: %s\n" "${TARGET_LIB}"
  else
    printf "Нет каталога: %s\n" "${TARGET_LIB}"
  fi

  # Do NOT wipe user's ~/.local trees; only tidy empty parents / НЕ очищаем весь ~/.local; только пробуем удалить пустые родительские каталоги
  if [[ "${MODE}" == "local" ]]; then
    # Attempt to remove empty BIN_DIR / Попытка удалить пустой BIN_DIR
    if [[ -d "${BIN_DIR}" ]] && rmdir "${BIN_DIR}" 2>/dev/null; then
      printf "Удален пустой каталог: %s\n" "${BIN_DIR}"
    fi
    # Attempt to remove empty LIB_DIR / Попытка удалить пустой LIB_DIR
    if [[ -d "${LIB_DIR}" ]] && rmdir "${LIB_DIR}" 2>/dev/null; then
      printf "Удален пустой каталог: %s\n" "${LIB_DIR}"
    fi
  fi

  printf "Готово.\n"
}

# PATH flags (local only) / Обработка флагов PATH (только для локального режима)
if [[ "${MODE}" == "local" && "${FLAG_PATH}" == "1" ]]; then
  print_path_hint
  exit 0
fi

if [[ "${MODE}" == "local" && "${FLAG_UPDATE_PATH}" == "1" ]]; then
  auto_update_path
  exit 0
fi

# Execute action / Выполнение действия
case "${ACTION}" in
  install)
    do_install ;;
  uninstall)
    do_uninstall ;;
  *)
    printf "ERROR: Неизвестное действие: %s\n" "${ACTION}" >&2
    exit 1 ;;
esac
#
# BS installer (Linux)
# Установщик BS (Linux)
#
# Режимы / Modes:
#   1) System install (нужен sudo/root) / Системная установка (нужен sudo/root):
#        sudo ./install.sh
#        sudo ./install.sh install
#
#   2) Local install (без sudo) в ~/.local / Локальная установка (без sudo) в ~/.local:
#        ./install.sh --local
#        ./install.sh --local install
#
# Удаление / Uninstall:
#   sudo ./install.sh uninstall
#   ./install.sh --local uninstall
#
# PATH helper / Помощник PATH:
# ./install.sh --local --path # печатает, что добавить в shell rc / печатает, что добавить
# в shell rc
# ./install.sh --local --update-path # добавляет в ~/.bashrc (с подтверждением) /
# добавляет в ~/.bashrc (с подтверждением)
#
# Переопределения (опционально)
#   PREFIX=... BIN_DIR=... LIB_DIR=...
#

# Безопасные настройки / Safe settings:
#   -e: выход при ошибке любой команды / exit on error of any command
#   -u: ошибка при использовании неопределенных переменных / error on use of undefined
# variables
#   -o pipefail: ошибка пайплайна если любая команда пайплайна упала / pipeline error if any
# pipeline command failed
set -euo pipefail  # Устанавливаем строгие параметры оболочки: -e (выходить при ошибках), -u (ошибки при неопределённых переменных), -o pipefail (ошибки в конвейерах)

check_shell_environment() {
    # Determine shell name from environment variables or $0
    local shell_name="${ZSH_VERSION:+zsh}${BASH_VERSION:+bash}${KSH_VERSION:+ksh}"
    
    # If shell wasn't detected from version vars, check $0
    if [[ -z "$shell_name" ]]; then
        case "${0##*/}" in
            *bash*) shell_name="bash" ;;
            *zsh*) shell_name="zsh" ;;
            *ksh*) shell_name="ksh" ;;
            *sh)   shell_name="sh" ;;
            *)      shell_name="${0##*/}" ;;
        esac
    fi

    # Check if the shell is supported
    case "$shell_name" in
        bash|zsh|ksh|sh) return 0 ;;
        *)
            printf "ERROR: Unsupported shell: %s\n" "$shell_name" >&2
            printf "This script requires bash, zsh, ksh, or sh to run.\n" >&2
            exit 1
            ;;
    esac
}

# Проверяем окружение оболочки перед продолжением
check_shell_environment  # Вызываем функцию проверки оболочки

# Функция показа справки
# Function to show help
usage() {  # Функция вывода справки
	cat <<'HELP'  # Выводим текст справки
Bs installer

Usage:
  ./install.sh [--local] [install|uninstall] [--path|--update-path]
  sudo ./install.sh [install|uninstall]

Examples:
  sudo ./install.sh
  sudo ./install.sh install
  sudo ./install.sh uninstall

  ./install.sh --local
  ./install.sh --local install
  ./install.sh --local uninstall

  ./install.sh --local --path
  ./install.sh --local --update-path
HELP
}

# Функция подтверждения действия
confirm() {  # Функция запроса подтверждения у пользователя
	local prompt="$1"  # Сохраняем сообщение запроса в переменную
	local ans  # Объявляем переменную для ответа

	read -r -p "${prompt} [y/N]: " ans  # Читаем ответ пользователя с подсказкой
	# Возвращает 0 (true) только если ответ y или Y
	[[ "${ans}" == "y" || "${ans}" == "Y" ]]  # Проверяем, равен ли ответ "y" или "Y"
}

# Парсинг аргументов
MODE="system"        # system|local - режим установки
ACTION="install"     # install|uninstall - действие
FLAG_PATH="0"        # 0|1 - флаг печати PATH сниппета
FLAG_UPDATE_PATH="0" # 0|1 - флаг обновления ~/.bashrc

while [[ $# -gt 0 ]]; do  # Цикл обработки аргументов командной строки
	case "$1" in  # Проверяем текущий аргумент
	--local)  # Если аргумент --local
		MODE="local"  # Устанавливаем режим в локальный
		shift  # Переходим к следующему аргументу
		;;
	--path)  # Если аргумент --path
		FLAG_PATH="1"  # Устанавливаем флаг вывода PATH
		shift  # Переходим к следующему аргументу
		;;
	--update-path)  # Если аргумент --update-path
		FLAG_UPDATE_PATH="1"  # Устанавливаем флаг обновления PATH
		shift  # Переходим к следующему аргументу
		;;
	-h | --help)  # Если аргумент -h или --help
		usage  # Выводим справку
		exit 0  # Выходим с кодом успеха
		;;
	install | uninstall | remove)  # Если аргумент install, uninstall или remove
		ACTION="$1"  # Сохраняем действие
		shift  # Переходим к следующему аргументу
		;;
	*)  # Для любого другого аргумента
		printf "ERROR: %s\n" "Неизвестный аргумент: $1 (см. --help)" >&2  # Выводим ошибку в stderr
		exit 1  # Выходим с кодом ошибки
		;;
	esac
done

# Синоним для команды remove
if [[ "${ACTION}" == "remove" ]]; then  # Если действие - remove
	ACTION="uninstall"  # Заменяем на uninstall
fi

# Определение абсолютного пути.
# Корневой директории вызова ./install т.е. исходников
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"  # Получаем абсолютный путь к каталогу скрипта
SOURCE_ROOT="$(dirname "${SCRIPT_DIR}")"  # Идем на уровень выше от bootstrap директории для получения исходников

# Определение целевых директорий
# Выбираем PREFIX в зависимости от режима
if [[ "${MODE}" == "local" ]]; then  # Если выбран локальный режим
	# Для локальной установки: ~/.local
	# ${PREFIX:="$HOME/.local"}: если PREFIX не задан, используем ~/.local
	: "${PREFIX:="$HOME/.local"}"  # Устанавливаем PREFIX в ~/.local, если не задан
else
	# Для системной установки: /usr/local
	: "${PREFIX:=/usr/local}"  # Устанавливаем PREFIX в /usr/local, если не задан
fi

# Определение BIN_DIR и LIB_DIR с умолчаниями:
# Синтаксис ${VAR:=default} проверяет, установлена ли переменная VAR.
# Если нет (или пустая), присваивает ей значение default.
# : перед кавычками - это no-op команда, которая только выполняет подстановку.
: "${BIN_DIR:="${PREFIX}/bin"}" # Если BIN_DIR не задан, используем ${PREFIX}/bin
: "${LIB_DIR:="${PREFIX}/lib"}" # Если LIB_DIR не задан, используем ${PREFIX}/lib

# Финальные пути установки
TARGET_LIB="${LIB_DIR}/bs" # Директория для библиотек BS
TARGET_BIN="${BIN_DIR}/bs" # Исполняемый файл

# Функция проверки, установлена ли система
is_already_installed() {  # Функция проверки наличия установленной системы
	if [[ -d "${TARGET_LIB}" && -f "${TARGET_BIN}" ]]; then  # Проверяем существование каталога библиотек и исполняемого файла
		return 0  # Уже установлена / Already installed
	else
		return 1  # Не установлена / Not installed yet
	fi
}

# Функция для генерации сниппета PATH для добавления в shell rc файлы
path_snippet() {  # Функция вывода сниппета для добавления в PATH
	cat <<'SNIP'  # Выводим текст сниппета
# Bs (local) - add to PATH
export PATH="$HOME/.local/bin:$PATH"
SNIP
}

# Печать подсказки по настройке PATH
print_path_hint() {  # Функция вывода подсказки по настройке PATH
	printf "Чтобы работало: #!/usr/bin/env bs\n"  # Выводим инструкцию по использованию
	printf "Добавь ~/.local/bin в PATH. Например, в ~/.bashrc:\n"  # Объясняем, как добавить в PATH
	printf "\n"  # Пустая строка
	path_snippet  # Выводим сниппет
	printf "\n"  # Пустая строка
}

# Функция добавления PATH в ~/.bashrc
update_path_bashrc() {  # Функция обновления ~/.bashrc
	local bashrc="${HOME}/.bashrc"  # Путь к файлу ~/.bashrc
	local line="export PATH=\"\$HOME/.local/bin:\$PATH\""  # Строка для добавления в ~/.bashrc

	# Создаем файл если не существует
	[[ -f "${bashrc}" ]] || touch "${bashrc}"  # Создаем ~/.bashrc, если он не существует

	# Проверяем, не добавлена ли уже строка
	if grep -Fqx "${line}" "${bashrc}"; then  # Проверяем, содержится ли строка в ~/.bashrc
		printf "PATH уже настроен в %s\n" "${bashrc}"  # Сообщаем, что PATH уже настроен
		return 0
	fi

	# Запрашиваем подтверждение
	if confirm "Добавить PATH в ${bashrc}?"; then  # Запрашиваем подтверждение у пользователя
		# Добавляем строку в конец файла
		printf "\n%s\n" "${line}" >>"${bashrc}"  # Добавляем строку в конец ~/.bashrc
		printf "Добавлено. Применить: source ~/.bashrc\n"  # Сообщаем, что изменения применены
	else
		printf "Пропущено.\n"  # Сообщаем, что изменение пропущено
	fi
}

# Функция автоматического добавления PATH в ~/.bashrc и ~/.zshrc без подтверждения
auto_update_path() {  # Функция автоматического обновления файлов оболочек
	local bashrc="${HOME}/.bashrc"  # Путь к файлу ~/.bashrc
	local zshrc="${HOME}/.zshrc"   # Путь к файлу ~/.zshrc
	local line="export PATH=\"\$HOME/.local/bin:\$PATH\""  # Строка для добавления в оба файла

	# Обновляем ~/.bashrc
	if [[ -f "${bashrc}" ]] || [[ ! -f "${zshrc}" ]]; then  # Если .bashrc существует или .zshrc не существует
		# Проверяем, не добавлена ли уже строка
		if ! grep -Fqx "${line}" "${bashrc}" 2>/dev/null; then  # Проверяем, содержится ли строка в ~/.bashrc
			# Добавляем строку в конец файла
			printf "\n%s\n" "${line}" >>"${bashrc}"  # Добавляем строку в конец ~/.bashrc
			printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${bashrc}"  # Сообщаем, что изменения применены
		else
			printf "PATH уже настроен в %s\n" "${bashrc}"  # Сообщаем, что PATH уже настроен
		fi
	fi

	# Обновляем ~/.zshrc
	if [[ -f "${zshrc}" ]]; then  # Если .zshrc существует
		# Проверяем, не добавлена ли уже строка
		if ! grep -Fqx "${line}" "${zshrc}" 2>/dev/null; then  # Проверяем, содержится ли строка в ~/.zshrc
			# Добавляем строку в конец файла
			printf "\n%s\n" "${line}" >>"${zshrc}"  # Добавляем строку в конец ~/.zshrc
			printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${zshrc}"  # Сообщаем, что изменения применены
		else
			printf "PATH уже настроен в %s\n" "${zshrc}"  # Сообщаем, что PATH уже настроен
		fi
	fi
}

# Функция установки
do_install() {  # Функция выполнения установки
	# Проверка прав для системной установки
	if [[ "${MODE}" == "system" ]]; then  # Если режим системной установки
		# ${EUID:-$(id -u)}: использует EUID если определена, иначе получает через id -u
		if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then  # Проверяем, запущен ли скрипт от root
			printf "ERROR: %s\n" "Нужны права root. Запусти: sudo ./install.sh" >&2  # Выводим сообщение об ошибке
			exit 1  # Выходим с кодом ошибки
		fi
	fi

	# Проверяем, установлена ли система уже
	if is_already_installed; then  # Проверяем, установлена ли система
		printf "Предупреждение: Bs уже установлена в %s\n" "${TARGET_LIB}"  # Выводим предупреждение
		printf "Удалите сначала старую версию командой: ./install.sh uninstall\n"  # Подсказываем, как удалить старую версию
		printf "Или используйте переопределения: PREFIX=... BIN_DIR=... LIB_DIR=...\n"  # Подсказываем, как переопределить пути
		exit 1  # Выходим с кодом ошибки
	fi

	printf "Установка Bs (%s)\n" "${MODE}"  # Выводим информацию о начале установки
	printf "  SOURCE_ROOT: %s\n" "${SOURCE_ROOT}"  # Выводим путь к исходникам
	printf "  PREFIX:      %s\n" "${PREFIX}"  # Выводим префикс установки
	printf "  TARGET_LIB:  %s\n" "${TARGET_LIB}"  # Выводим путь к каталогу библиотек
	printf "  TARGET_BIN:  %s\n" "${TARGET_BIN}"  # Выводим путь к исполняемому файлу

	# Создаем целевые директории если их нет
	mkdir -p "${BIN_DIR}"  # Создаем каталог для исполняемых файлов
	mkdir -p "${LIB_DIR}"  # Создаем каталог для библиотек

	# Очищаем старую установку
	rm -rf "${TARGET_LIB}"  # Удаляем старую установку из каталога библиотек
	mkdir -p "${TARGET_LIB}"  # Создаем каталог библиотек заново

	# Копируем файлы BS
	cp -a "${SOURCE_ROOT}/bootstrap" "${TARGET_LIB}/"  # Копируем каталог bootstrap
	cp -a "${SOURCE_ROOT}/core" "${TARGET_LIB}/"  # Копируем каталог core
	cp -a "${SOURCE_ROOT}/bs" "${TARGET_LIB}/"  # Копируем файл bs (был BS)
	cp -a "${SOURCE_ROOT}/lib" "${TARGET_LIB}/"  # Копируем каталог lib

	# Создаем wrapper-скрипт
	if [[ "${MODE}" == "local" ]]; then
		# Для локальной установки используем ~/.local/lib/bs как путь
		cat >"${TARGET_BIN}" <<WRAP
#!/usr/bin/env bash
export BOSA_ROOT="\$HOME/.local/lib/bs"
exec "\$BOSA_ROOT/bs" "\$@"
WRAP
	else
		# Для системной установки используем /usr/local/lib/bs как путь
		cat >"${TARGET_BIN}" <<WRAP
#!/usr/bin/env bash
export BOSA_ROOT="/usr/local/lib/bs"
exec "\$BOSA_ROOT/bs" "\$@"
WRAP
	fi

	chmod 0755 "${TARGET_BIN}"  # Делаем файл исполняемым

	printf "Готово.\n"  # Выводим сообщение о завершении

	# Для локальной установки автоматически добавляем путь в PATH
	if [[ "${MODE}" == "local" ]]; then  # Если режим локальной установки
		auto_update_path  # Автоматически добавляем путь в файлы оболочек
	fi
}

# Функция удаления
do_uninstall() {  # Функция выполнения удаления
	# Проверка прав для системного удаления
	if [[ "${MODE}" == "system" ]]; then  # Если режим системной установки
		# ${EUID:-$(id -u)}: использует EUID если определена, иначе получает через id -u
		if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then  # Проверяем, запущен ли скрипт от root
			printf "ERROR: %s\n" "Нужны права root. Запусти: sudo ./install.sh" >&2  # Выводим сообщение об ошибке
			exit 1  # Выходим с кодом ошибки
		fi
	fi

	printf "Удаление Bs (%s)\n" "${MODE}"  # Выводим информацию о начале удаления
	printf "  TARGET_BIN: %s\n" "${TARGET_BIN}"  # Выводим путь к исполняемому файлу
	printf "  TARGET_LIB: %s\n" "${TARGET_LIB}"  # Выводим путь к каталогу библиотек

	# Удаляем исполняемый файл
	if [[ -f "${TARGET_BIN}" ]]; then  # Проверяем существование исполняемого файла
		rm -f "${TARGET_BIN}"  # Удаляем исполняемый файл
		printf "Удален: %s\n" "${TARGET_BIN}"  # Сообщаем об удалении файла
	else
		printf "Нет файла: %s\n" "${TARGET_BIN}"  # Сообщаем, что файла не существует
	fi

	# Удаляем директорию с библиотеками
	if [[ -d "${TARGET_LIB}" ]]; then  # Проверяем существование каталога библиотек
		rm -rf "${TARGET_LIB}"  # Удаляем каталог библиотек
		printf "Удален: %s\n" "${TARGET_LIB}"  # Сообщаем об удалении каталога
	else
		printf "Нет каталога: %s\n" "${TARGET_LIB}"  # Сообщаем, что каталога не существует
	fi

	# При локальной установке дополнительно очищаем ~/.local/lib и ~/.local/bin
	if [[ "${MODE}" == "local" ]]; then
		local local_lib_dir="${HOME}/.local/lib"
		local local_bin_dir="${HOME}/.local/bin"
		
		if [[ -d "${local_lib_dir}" ]]; then
			rm -rf "${local_lib_dir}/*"
			printf "Очищен каталог: %s\n" "${local_lib_dir}"
		fi
		
		if [[ -d "${local_bin_dir}" ]]; then
			rm -rf "${local_bin_dir}/*"
			printf "Очищен каталог: %s\n" "${local_bin_dir}"
		fi
	fi

	printf "Готово.\n"  # Выводим сообщение о завершении
}

# Обработка флагов PATH (только для локального режима)
if [[ "${MODE}" == "local" && "${FLAG_PATH}" == "1" ]]; then  # Если локальный режим и флаг PATH установлен
	print_path_hint  # Выводим подсказку по PATH
	exit 0  # Выходим с кодом успеха
fi

if [[ "${MODE}" == "local" && "${FLAG_UPDATE_PATH}" == "1" ]]; then  # Если локальный режим и флаг обновления PATH установлен
	auto_update_path  # Автоматически обновляем ~/.bashrc и ~/.zshrc без подтверждения
	exit 0  # Выходим с кодом успеха
fi

# Выполнение основного действия
case "${ACTION}" in  # Проверяем действие
install)  # Если действие install
	do_install  # Выполняем установку
	;;
uninstall)  # Если действие uninstall
	do_uninstall  # Выполняем удаление
	;;
*)  # Для любого другого действия
	printf "ERROR: %s\n" "Неизвестное действие: ${ACTION}" >&2  # Выводим ошибку
	exit 1  # Выходим с кодом ошибки
	;;
esac