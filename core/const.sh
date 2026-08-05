#!/usr/bin/env bash
#
# core/const.sh 
# — константы ошибок и кодов возврата фреймворка BS
# — error constants and return codes for BS framework
#
# Этот модуль определяет стандартные коды возврата и константы,
# используемые во всем фреймворке для обеспечения консистентности.
#
# This module defines standard return codes and constants used
# throughout the framework to ensure consistency.
#

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Core prerequisites
source "$(dirname -- "${BASH_SOURCE[0]}")/prereq.sh"
bs::guard "CONST" || return 0

#
# Базовые коды возврата / Basic return codes
#

# Успешное выполнение / Successful execution
readonly E_SUCCESS=0

# Общая ошибка / General error
readonly E_ERROR=1

# Неверные аргументы или параметры / Invalid arguments or parameters
readonly E_INVALID=2

# 
# Расширенные коды ошибок / Extended error codes
# 

# Неверные аргументы функции / Invalid function arguments
readonly LIB_ERROR_INVALID_ARGS=3

# Неверный входной формат данных / Invalid input data format
readonly LIB_ERROR_INVALID_INPUT=4

# Файл не найден / File not found
readonly LIB_ERROR_FILE_NOT_FOUND=5

# Отказано в доступе / Permission denied
readonly LIB_ERROR_PERMISSION_DENIED=6

# Ошибка зависимости / Dependency error
readonly LIB_ERROR_DEPENDENCY=7

# Неподдерживаемая операционная система / Unsupported operating system
readonly LIB_ERROR_UNSUPPORTED_OS=8

# Таймаут операции / Operation timeout
readonly LIB_ERROR_TIMEOUT=9

# Конфликт ресурсов / Resource conflict
readonly LIB_ERROR_CONFLICT=10

# Ошибка файловой операции / File operation error
readonly LIB_ERROR_FILE_OPERATION=100

# Отсутствует зависимость / Dependency missing
readonly LIB_ERROR_DEPENDENCY_MISSING=101

# Платформа не поддерживается / Platform unsupported
readonly LIB_ERROR_PLATFORM_UNSUPPORTED=102

#
# Коды ошибок интеграций / Integration error codes
# Диапазон 200–249 зарезервирован для integration-модулей.
# Range 200–249 is reserved for integration modules.

# Ошибка HTTP-запроса / HTTP request error
readonly INTEGRATION_ERROR_HTTP=200

# Ошибка LLM-провайдера / LLM provider error
readonly INTEGRATION_ERROR_LLM=201

# Ошибка Kubernetes / Kubernetes error
readonly INTEGRATION_ERROR_K8S=202

# Отсутствует внешняя зависимость модуля / Module external dependency missing
readonly INTEGRATION_ERROR_MISSING_DEPS=203

#
# Коды ошибок модулей / Module error codes
# Диапазон 210–239 зарезервирован для generic module errors.
# Range 210–239 is reserved for generic module errors.

# Ошибка конфигурации / Configuration error
readonly MODULE_ERROR_CONFIG=210

# 
# Глобальные переменные фреймворка / Framework global variables
# 

# Режим отладки / Debug mode
declare -g FRAMEWORK_DEBUG=false

# Режим "сухого запуска" (без выполнения действий) / Dry run mode (no actions executed)
declare -g FRAMEWORK_DRY_RUN=false

# Версия фреймворка / Framework version
# Владелец переменной — скрипт bs (readonly); здесь задаём только если пусто
# Owner of the variable is the bs script (readonly); set here only if empty
if [[ -z "${BS_VERSION:-}" ]]; then
  declare -g BS_VERSION="0.3.0"
fi

# 
# Константы для цветового вывода / Color output constants
# 

# ANSI escape sequences / ANSI escape последовательности
readonly COLOR_RESET='\033[0m'
readonly COLOR_BLACK='\033[0;30m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_PURPLE='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[0;37m'

# Яркие цвета / Bright colors
readonly COLOR_BRIGHT_BLACK='\033[0;90m'
readonly COLOR_BRIGHT_RED='\033[0;91m'
readonly COLOR_BRIGHT_GREEN='\033[0;92m'
readonly COLOR_BRIGHT_YELLOW='\033[0;93m'
readonly COLOR_BRIGHT_BLUE='\033[0;94m'
readonly COLOR_BRIGHT_PURPLE='\033[0;95m'
readonly COLOR_BRIGHT_CYAN='\033[0;96m'
readonly COLOR_BRIGHT_WHITE='\033[0;97m'

# 
# Константы для форматирования / Formatting constants
# 

# Символы для спиннеров и индикаторов / Spinner and indicator characters
readonly SPINNER_CHARS='/-\|'
readonly PROGRESS_BLOCK='█'
readonly PROGRESS_EMPTY=' '

# 
# Константы для системных путей / System path constants
# 

# Стандартные системные каталоги / Standard system directories
readonly SYS_ETC="/etc"
readonly SYS_VAR="/var"
readonly SYS_TMP="/tmp"
readonly SYS_USR_LOCAL="/usr/local"
readonly SYS_HOME="${HOME}"

# 
# Массивы констант для валидации / Constant arrays for validation
# 

# Поддерживаемые дистрибутивы Linux / Supported Linux distributions
readonly SUPPORTED_DISTROS=("alma" "centos" "rhel" "fedora" "debian" "ubuntu")

# Разрешенные символы для имен файлов / Allowed characters for filenames
readonly FILENAME_ALLOWED_CHARS='[a-zA-Z0-9._-]'

# 
# Функции для работы с константами / Constant utility functions
# 

# @description Check if error code is valid / Проверить валидность кода ошибки
# @param $1 Error code to check / Код ошибки для проверки
# @return E_SUCCESS if valid, E_ERROR otherwise / E_SUCCESS если валиден, иначе E_ERROR
const::is_valid_error_code() {
    local -r code="${1:?Missing error code}"

    case "${code}" in
        0|1|2|3|4|5|6|7|8|9|10|100|101|102|200|201|202|203|210)
            return "${E_SUCCESS}"
            ;;
        *)
            return "${E_ERROR}"
            ;;
    esac
}

# @description Get error description by code / Получить описание ошибки по коду
# @param $1 Error code / Код ошибки
# @return Error description / Описание ошибки
const::error_description() {
    local -r code="${1:?Missing error code}"

    case "${code}" in
        0) printf '%s\n' "Success / Успешно" ;;
        1) printf '%s\n' "General error / Общая ошибка" ;;
        2) printf '%s\n' "Invalid arguments / Неверные аргументы" ;;
        3) printf '%s\n' "Invalid function arguments / Неверные аргументы функции" ;;
        4) printf '%s\n' "Invalid input data format / Неверный формат входных данных" ;;
        5) printf '%s\n' "File not found / Файл не найден" ;;
        6) printf '%s\n' "Permission denied / Отказано в доступе" ;;
        7) printf '%s\n' "Dependency error / Ошибка зависимости" ;;
        8) printf '%s\n' "Unsupported OS / Неподдерживаемая ОС" ;;
        9) printf '%s\n' "Operation timeout / Таймаут операции" ;;
        10) printf '%s\n' "Resource conflict / Конфликт ресурсов" ;;
        100) printf '%s\n' "File operation error / Ошибка файловой операции" ;;
        101) printf '%s\n' "Dependency missing / Отсутствует зависимость" ;;
        102) printf '%s\n' "Platform unsupported / Платформа не поддерживается" ;;
        200) printf '%s\n' "HTTP request error / Ошибка HTTP-запроса" ;;
        201) printf '%s\n' "LLM provider error / Ошибка LLM-провайдера" ;;
        202) printf '%s\n' "Kubernetes error / Ошибка Kubernetes" ;;
        203) printf '%s\n' "Module external dependency missing / Отсутствует внешняя зависимость модуля" ;;
        210) printf '%s\n' "Configuration error / Ошибка конфигурации" ;;
        *) printf '%s\n' "Unknown error / Неизвестная ошибка" ;;
    esac
}

# @description Get framework version / Получить версию фреймворка
# @return Framework version string / Строка версии фреймворка
const::version() {
    printf '%s\n' "${BS_VERSION}"
}