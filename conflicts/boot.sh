#!/usr/bin/env bash
# Bs Framework - Project Launcher
# This script serves as the initial entry point for the BS framework
# Project boot entrypoint
# Finds BS_ROOT and chains to main launcher

# Точка входа проекта
# Находит BS_ROOT и передаёт управление основному лаунчеру.

set -euo pipefail

# Check for minimum bash version (4.0+)
if [[ ${BASH_VERSION%%.*} -lt 4 ]]; then
    echo "Error: This script requires Bash version 4.0 or higher." >&2
    exit 1
fi

show_usage() {
    echo "BS Framework - Project Launcher"
    echo "Usage:"
    echo "  ./boot.sh [command]"
    echo ""
    echo "Commands:"
    echo "  help, --help, -h     Show this help message"
    echo "  version              Show framework version"
    echo "  env                  Show environment information"
    echo "  list                 List available modules"
    echo "  doctor               Check framework integrity"
    echo "  run <script>         Run a script with BS framework"
    echo "  init-shell           Generate shell initialization commands"
    echo ""
    echo "Examples:"
    echo "  ./boot.sh --help"
    echo "  ./boot.sh version"
    echo "  ./boot.sh run examples/ps1configurationexample.sh"
    echo "  ./boot.sh run example/bs_test.sh"
}

# Try to determine BS_ROOT based on the location of this script
# Resolve BS_ROOT near this file or from env / Определяем BS_ROOT рядом со скриптом или из окружения
if [[ -z "${BS_ROOT:-}" ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  # Try project-local layout: repo root has file 'bs' / Пробуем проектную раскладку: в корне есть 'bs'
  if [[ -f "${SCRIPT_DIR}/bs" ]]; then
    export BS_ROOT="${SCRIPT_DIR}"
  elif [[ -f "${SCRIPT_DIR}/lib/bs/bs" ]]; then
    export BS_ROOT="${SCRIPT_DIR}/lib/bs"
  else
    # Fallback to system/local install locations / Пытаемся найти системную установку
    for loc in "$HOME/.local/lib/bs" "/usr/local/lib/bs"; do
      if [[ -f "${loc}/bs" ]]; then
        export BS_ROOT="${loc}"
        break
      fi
    done
  fi
fi

# Check if we're in the project root (with bootstrap/init.sh present)
if [[ -f "${SCRIPT_DIR}/bootstrap/init.sh" ]]; then
    BS_ROOT="${SCRIPT_DIR}"
else
    # Look for installed versions
    if [[ -d "${HOME}/.local/lib/bs" && -f "${HOME}/.local/lib/bs/bootstrap/init.sh" ]]; then
        BS_ROOT="${HOME}/.local/lib/bs"
    elif [[ -d "/usr/local/lib/bs" && -f "/usr/local/lib/bs/bootstrap/init.sh" ]]; then
        BS_ROOT="/usr/local/lib/bs"
    else
        echo "Error: Could not locate BS framework root." >&2
        exit 1
    fi
fi

# Export BS_ROOT so that the bs script can use it
export BS_ROOT

# Delegate everything to the main bs script
exec "${BS_ROOT}/bs" "$@"
BS_PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"  # Получаем абсолютный путь к каталогу, содержащему этот файл (boot.sh)
: "${BS_PROJECT_FRAMEWORK_DIR:="${BS_PROJECT_DIR}/bs"}"  # Устанавливаем путь к каталогу фреймворка, если он еще не задан; по умолчанию это ./bs
#
# ПОДКЛЮЧЕНИЕ МОДУЛЯ / MODULE IMPORT:
# Импортируется: "${BS_PROJECT_FRAMEWORK_DIR}/bs"
# Imports: "${BS_PROJECT_FRAMEWORK_DIR}/bs"
#
# Load framework entrypoint
if [[ -f "${BS_PROJECT_FRAMEWORK_DIR}/BS" ]]; then  # Проверяем, существует ли главный файл фреймворка
    . source "${BS_PROJECT_FRAMEWORK_DIR}/BS"  # Подключаем главный файл фреймворка с помощью оператора source
else
    echo "Framework file not found: ${BS_PROJECT_FRAMEWORK_DIR}/BS" >&2  # Выводим сообщение об ошибке в stderr
    exit 1  # Завершаем выполнение с кодом ошибки
fi

# Удаляем переменную, так как она больше не нужна
unset BS_PROJECT_DIR