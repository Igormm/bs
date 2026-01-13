#!/usr/bin/env bash
# BS bootstrap initializer / Инициализатор бутстрапа BS
# Purpose: detect project root, export BS_ROOT, and source core bootstrap pieces.
# Назначение: определить корень проекта, экспортировать BS_ROOT и подключить ядро.

set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  printf "ERROR: This script requires bash.\n" >&2
  printf "Скрипт требует bash. Запустите: bash /bootstrap/init.sh\n" >&2
  exit 1
fi

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

# If executed directly, warn and offer help / Если запущен напрямую — предупреждение и помощь
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf "WARNING: Must be sourced: source %s\n" "$0"
  printf "ВНИМАНИЕ: Скрипт нужно вызывать через source: source %s\n" "$0"
  usage
  exit 1
fi

# Resolve BS_ROOT / Определяем BS_ROOT
# Priority: existing BS_ROOT -> from this file location -> fallback error
if [[ -n "${BS_ROOT:-}" && -d "${BS_ROOT}" ]]; then
  :
else
  THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  CANDIDATE="$(cd -- "${THIS_DIR}/.." && pwd)"
  if [[ -d "${CANDIDATE}" && -f "${CANDIDATE}/bs" ]]; then
    export BS_ROOT="${CANDIDATE}"
  else
    printf "ERROR: Unable to determine BS_ROOT. Set BS_ROOT environment variable.\n" >&2
    printf "ОШИБКА: Не удалось определить BS_ROOT. Установите переменную окружения BS_ROOT.\n" >&2
    return 1
  fi
fi

# Minimal PATH sanity for local installs / Базовая настройка PATH для локальных установок
# Adds ~/.local/bin if not present
append_local_bin_to_path() {
  local needle="$HOME/.local/bin"
  case ":$PATH:" in
    *":${needle}:"*) return 0 ;;
    *) export PATH="${needle}:${PATH}" ;;
  esac
}
append_local_bin_to_path

# Source core bootstrap pieces if present / Подключаем ядро, если есть
# These are optional; missing files produce warnings only.
source_if_exists() {
  local f="$1"
  if [[ -f "$f" ]]; then
    # shellcheck disable=SC1090
    source "$f"
  else
    printf "Notice: optional component not found: %s\n" "$f"
    printf "Примечание: необязательный компонент не найден: %s\n" "$f"
  fi
}

# Typical layout / Типовая раскладка
source_if_exists "${BS_ROOT}/core/env.sh"
source_if_exists "${BS_ROOT}/core/aliases.sh"
source_if_exists "${BS_ROOT}/core/functions.sh"

# Export a small flag to indicate bootstrap complete / Флаг завершения инициализации
export BS_BOOTSTRAPPED=1

# Brief info message (can be silenced by BS_SILENT=1) / Краткое сообщение (можно скрыть BS_SILENT=1)
if [[ "${BS_SILENT:-0}" != "1" ]]; then
  printf "BS bootstrap initialized from: %s\n" "${BS_ROOT}"
  printf "Бутстрап BS инициализирован из: %s\n" "${BS_ROOT}"
fi
# Этот файл обеспечивает идемпотентную инициализацию всех компонентов фреймворка.
# This file provides idempotent initialization of all framework components.
#

set -euo pipefail  # Устанавливаем строгие параметры оболочки: -e (выходить при ошибках), -u (ошибки при неопределённых переменных), -o pipefail (ошибки в конвейерах)

# Проверка идемпотентности 
# Idempotency check
if [[ -n "${BOSA_INITIALIZED:-}" ]]; then  # Проверяем, была ли уже инициализирована среда BS
    log::debug "BS already initialized, skipping" 2>/dev/null || true  # Выводим отладочное сообщение, если логирование доступно
    return 0  # Возвращаемся, если инициализация уже выполнена
fi

# Определение BOSA_ROOT если не установлен 
# Define BOSA_ROOT if not set
if [[ -z "${BOSA_ROOT:-}" ]]; then  # Проверяем, установлена ли переменная BOSA_ROOT
    BOSA_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"  # Устанавливаем BOSA_ROOT в родительский каталог от текущего файла (init.sh)
    export BOSA_ROOT  # Экспортируем переменную в окружение
fi

# Загрузка loader 
# Loading loader
if [[ -f "${BOSA_ROOT}/bootstrap/loader.sh" ]]; then  # Проверяем наличие loader.sh в подкаталоге bootstrap
    source "${BOSA_ROOT}/bootstrap/loader.sh"  # Загружаем файл loader.sh
elif [[ -f "${BOSA_ROOT}/loader.sh" ]]; then  # Альтернативно, проверяем наличие loader.sh в корне фреймворка
    source "${BOSA_ROOT}/loader.sh"  # Загружаем файл loader.sh из корня
else
    echo "BS: error: loader.sh not found in ${BOSA_ROOT}/bootstrap/ or ${BOSA_ROOT}/" >&2  # Выводим ошибку, если loader.sh не найден
    exit 1  # Завершаем скрипт с кодом ошибки
fi

# Загрузка ядра
# Loading core
load "core/const"  # Загружаем модуль констант
load "core/logger"  # Загружаем модуль логирования
load "core/errorhandler"  # Загружаем модуль обработки ошибок
load "core/version"  # Загружаем модуль версий

# Установка флага инициализации 
# Setting initialization flag
export BOSA_INITIALIZED="1"  # Устанавливаем флаг, сигнализирующий, что инициализация выполнена

log::debug "BS framework initialized successfully" 2>/dev/null || true  # Выводим сообщение об успешной инициализации, если доступно логирование