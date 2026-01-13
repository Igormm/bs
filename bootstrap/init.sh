#!/usr/bin/env bs
# shellcheck shell=bash
#
# bootstrap/init.sh — единая инициализация фреймворка 
# BS unified BS framework initialization
#
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