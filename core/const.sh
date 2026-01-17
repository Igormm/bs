#!/usr/bin/env bs

# core/const.sh 
# — константы ошибок и кодов возврата фреймворка BS
# — error constants and return codes for BS framework
#
# Этот модуль определяет стандартные коды возврата и константы,
# используемые во всем фреймворке для обеспечения консистентности.
#
# This module defines standard return codes and constants used
# throughout the framework to ensure consistency.

set -euo pipefail

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
declare -r LIB_ERROR_INVALID_ARGS=3

# Неверный входной формат данных / Invalid input data format
declare -r LIB_ERROR_INVALID_INPUT=4

# Файл не найден / File not found
declare -r LIB_ERROR_FILE_NOT_FOUND=5

# Отказано в доступе / Permission denied
declare -r LIB_ERROR_PERMISSION_DENIED=6

# Ошибка зависимости / Dependency error
declare -r LIB_ERROR_DEPENDENCY=7

# Неподдерживаемая операционная система / Unsupported operating system
declare -r LIB_ERROR_UNSUPPORTED_OS=8

# Таймаут операции / Operation timeout
declare -r LIB_ERROR_TIMEOUT=9

# Конфликт ресурсов / Resource conflict
declare -r LIB_ERROR_CONFLICT=10

# 
# Глобальные переменные фреймворка / Framework global variables
# 

# Режим отладки / Debug mode
declare -g FRAMEWORK_DEBUG=false

# Режим "сухого запуска" (без выполнения действий) / Dry run mode (no actions executed)
declare -g FRAMEWORK_DRY_RUN=false

# Версия фреймворка / Framework version
declare -g BS_VERSION="0.3.0"

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
    local code="${1:?Missing error code}"
    
    case "$code" in
        0|1|2|3|4|5|6|7|8|9|10)
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
    local code="${1:?Missing error code}"
    
    case "$code" in
        0) echo "Success / Успешно" ;;
        1) echo "General error / Общая ошибка" ;;
        2) echo "Invalid arguments / Неверные аргументы" ;;
        3) echo "Invalid function arguments / Неверные аргументы функции" ;;
        4) echo "Invalid input data format / Неверный формат входных данных" ;;
        5) echo "File not found / Файл не найден" ;;
        6) echo "Permission denied / Отказано в доступе" ;;
        7) echo "Dependency error / Ошибка зависимости" ;;
        8) echo "Unsupported OS / Неподдерживаемая ОС" ;;
        9) echo "Operation timeout / Таймаут операции" ;;
        10) echo "Resource conflict / Конфликт ресурсов" ;;
        *) echo "Unknown error / Неизвестная ошибка" ;;
    esac
}

# @description Get framework version / Получить версию фреймворка
# @return Framework version string / Строка версии фреймворка
const::version() {
    echo "${BS_VERSION}"
}
