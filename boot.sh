#!/usr/bin/env bash
# Project boot entrypoint / Точка входа проекта
# Finds BS_ROOT and chains to main launcher. / Находит BS_ROOT и передаёт управление основному лаунчеру.

set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  printf "ERROR: This script requires bash.\n" >&2
  printf "Скрипт требует bash. Запустите: bash ./boot.sh\n" >&2
  exit 1
fi

usage() {
  cat <<'HELP'
BS boot

Usage:
  ./boot.sh [command] [args...]
  Examples / Примеры:
    ./boot.sh help
    ./boot.sh version
    ./boot.sh run examples/hello.sh

Notes:
  - boot.sh resolves BS_ROOT and executes the main launcher "bs".
  - boot.sh определяет BS_ROOT и запускает главный лаунчер "bs".
HELP
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
  usage
  exit 0
fi

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

if [[ -z "${BS_ROOT:-}" || ! -f "${BS_ROOT}/bs" ]]; then
  printf "ERROR: Cannot locate BS_ROOT or 'bs' launcher.\n" >&2
  printf "ОШИБКА: Не удалось найти BS_ROOT или лаунчер 'bs'. Установите BS или задайте BS_ROOT.\n" >&2
  exit 1
fi

# Execute main launcher / Запуск основного лаунчера
exec "${BS_ROOT}/bs" "$@"
# Фреймворк BS - Расширенное bash-скриптование
#
# НАЗНАЧЕНИЕ: Главный entrypoint фреймворка BS
# PURPOSE: Main entrypoint for BS framework
#
# ЗАВИСИМОСТИ: bash 4.0+, стандартные утилиты Linux
# DEPENDENCIES: bash 4.0+, standard Linux utilities
#
# ИСПОЛЬЗУЕТСЯ: Для инициализации фреймворка и загрузки модулей
# USAGE: For framework initialization and module loading
#
#

# boot.sh — bootstrap-файл проекта для подключения BS в bash-скриптах / project bootstrap

# file for connecting BS in bash scripts

#

# Использование / Usage:

#   source "./boot.sh"

#   BS::init

#

# Примечание / Note:

# - По умолчанию фреймворк ожидается в каталоге: ./bs / By default framework is expected

# in directory: ./bs

# - Можно переопределить путь так: / Can override path like this:

#     BS_PROJECT_FRAMEWORK_DIR="/path/to/BS" source "./boot.sh"

#



# Абсолютный путь к каталогу проекта (где лежит boot.sh) / Absolute path to project

# directory (where boot.sh is located)

BS_PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"  # Получаем абсолютный путь к каталогу, содержащему этот файл (boot.sh)


# Абсолютный путь к каталогу фреймворка (по умолчанию: <project>/BS) / Absolute path to

# framework directory (default: <project>/BS)

#
# ПЕРЕМЕННАЯ / VARIABLE:
# : "${BS_PROJECT_FRAMEWORK_DIR: - [Описание переменной]
# : "${BS_PROJECT_FRAMEWORK_DIR: - [Variable description]
#
: "${BS_PROJECT_FRAMEWORK_DIR:="${BS_PROJECT_DIR}/bs"}"  # Устанавливаем путь к каталогу фреймворка, если он еще не задан; по умолчанию это ./bs


# Подключаем entrypoint фреймворка (в каталоге фреймворка это файл "BS") / Connect

# framework entrypoint (in framework directory this is file "BS")

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


# Опционально: можно сразу инициализировать (если хочешь без явного BS::init) / Optional:

# can initialize immediately (if you want without explicit BS::init)

# BS::init

# load "path/to/module" # для загрузки дополнительных модулей / for loading additional

# modules


unset BS_PROJECT_DIR  # Удаляем переменную, так как она больше не нужна