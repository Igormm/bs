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

bs::guard "CONST" || return 0

#
# Базовые коды возврата / Basic return codes
#

# @global E_SUCCESS — Generic success code (category: error-const)
# @global E_SUCCESS — Код успеха (категория: error-const)
readonly E_SUCCESS=0

# @global E_ERROR — Generic error code (category: error-const)
# @global E_ERROR — Код общей ошибки (категория: error-const)
readonly E_ERROR=1

# @global E_INVALID — Invalid argument or state (category: error-const)
# @global E_INVALID — Неверный аргумент или состояние (категория: error-const)
readonly E_INVALID=2

# 
# Расширенные коды ошибок / Extended error codes
# 

# @global LIB_ERROR_INVALID_ARGS — Lib error: invalid arguments (category: error-const)
# @global LIB_ERROR_INVALID_ARGS — Ошибка lib: неверные аргументы (категория: error-const)
readonly LIB_ERROR_INVALID_ARGS=3

# @global LIB_ERROR_INVALID_INPUT — Lib error: invalid input data (category: error-const)
# @global LIB_ERROR_INVALID_INPUT — Ошибка lib: неверные входные данные (категория: error-const)
readonly LIB_ERROR_INVALID_INPUT=4

# @global LIB_ERROR_FILE_NOT_FOUND — Lib error: file not found (category: error-const)
# @global LIB_ERROR_FILE_NOT_FOUND — Ошибка lib: файл не найден (категория: error-const)
readonly LIB_ERROR_FILE_NOT_FOUND=5

# @global LIB_ERROR_PERMISSION_DENIED — Lib error: permission denied (category: error-const)
# @global LIB_ERROR_PERMISSION_DENIED — Ошибка lib: отказано в доступе (категория: error-const)
readonly LIB_ERROR_PERMISSION_DENIED=6

# @global LIB_ERROR_DEPENDENCY — Lib error: optional dependency missing (category: error-const)
# @global LIB_ERROR_DEPENDENCY — Ошибка lib: отсутствует опциональная зависимость (категория: error-const)
readonly LIB_ERROR_DEPENDENCY=7

# @global LIB_ERROR_UNSUPPORTED_OS — Lib error: unsupported OS (category: error-const)
# @global LIB_ERROR_UNSUPPORTED_OS — Ошибка lib: неподдерживаемая ОС (категория: error-const)
readonly LIB_ERROR_UNSUPPORTED_OS=8

# @global LIB_ERROR_TIMEOUT — Lib error: operation timed out (category: error-const)
# @global LIB_ERROR_TIMEOUT — Ошибка lib: таймаут операции (категория: error-const)
readonly LIB_ERROR_TIMEOUT=9

# @global LIB_ERROR_CONFLICT — Lib error: conflicting state (category: error-const)
# @global LIB_ERROR_CONFLICT — Ошибка lib: конфликт состояния (категория: error-const)
readonly LIB_ERROR_CONFLICT=10

# @global LIB_ERROR_FILE_OPERATION — Lib error: file operation failed (category: error-const)
# @global LIB_ERROR_FILE_OPERATION — Ошибка lib: сбой файловой операции (категория: error-const)
readonly LIB_ERROR_FILE_OPERATION=100

# @global LIB_ERROR_DEPENDENCY_MISSING — Lib error: required dependency missing (category: error-const)
# @global LIB_ERROR_DEPENDENCY_MISSING — Ошибка lib: отсутствует обязательная зависимость (категория: error-const)
readonly LIB_ERROR_DEPENDENCY_MISSING=101

# @global LIB_ERROR_PLATFORM_UNSUPPORTED — Lib error: platform not supported (category: error-const)
# @global LIB_ERROR_PLATFORM_UNSUPPORTED — Ошибка lib: платформа не поддерживается (категория: error-const)
readonly LIB_ERROR_PLATFORM_UNSUPPORTED=102

#
# Коды ошибок интеграций / Integration error codes
# Диапазон 200–249 зарезервирован для integration-модулей.
# Range 200–249 is reserved for integration modules.

# @global INTEGRATION_ERROR_HTTP — Integration error base: HTTP (category: error-const)
# @global INTEGRATION_ERROR_HTTP — База кодов ошибок интеграции: HTTP (категория: error-const)
readonly INTEGRATION_ERROR_HTTP=200

# @global INTEGRATION_ERROR_LLM — Integration error base: LLM (category: error-const)
# @global INTEGRATION_ERROR_LLM — База кодов ошибок интеграции: LLM (категория: error-const)
readonly INTEGRATION_ERROR_LLM=201

# @global INTEGRATION_ERROR_K8S — Integration error base: K8s (category: error-const)
# @global INTEGRATION_ERROR_K8S — База кодов ошибок интеграции: K8s (категория: error-const)
readonly INTEGRATION_ERROR_K8S=202

# @global INTEGRATION_ERROR_MISSING_DEPS — Integration error: missing dependencies (category: error-const)
# @global INTEGRATION_ERROR_MISSING_DEPS — Ошибка интеграции: отсутствуют зависимости (категория: error-const)
readonly INTEGRATION_ERROR_MISSING_DEPS=203

#
# Коды ошибок модулей / Module error codes
# Диапазон 210–239 зарезервирован для generic module errors.
# Range 210–239 is reserved for generic module errors.

# @global MODULE_ERROR_CONFIG — Module error base: configuration (category: error-const)
# @global MODULE_ERROR_CONFIG — База кодов ошибок модуля: конфигурация (категория: error-const)
readonly MODULE_ERROR_CONFIG=210

# 
# Глобальные переменные фреймворка / Framework global variables
# 

# @global FRAMEWORK_DEBUG — Framework flag: debug mode (category: framework-flag)
# @global FRAMEWORK_DEBUG — Флаг фреймворка: режим отладки (категория: framework-flag)
declare -g FRAMEWORK_DEBUG=false

# @global FRAMEWORK_DRY_RUN — Framework flag: dry run (no actions executed) (category: framework-flag)
# @global FRAMEWORK_DRY_RUN — Флаг фреймворка: «сухой запуск» (без действий) (категория: framework-flag)
declare -g FRAMEWORK_DRY_RUN=false

# Версия фреймворка / Framework version
# Владелец переменной — core/version.sh; здесь задаём только если пусто
# Owner of the variable is core/version.sh; set here only if empty
if is::empty "${BS_VERSION:-}"; then
  declare -g BS_VERSION="0.6.0"
fi

# 
# Константы для цветового вывода / Color output constants
# 

# @global COLOR_RESET — ANSI color escape: reset (category: constant)
# @global COLOR_RESET — ANSI-escape цвета: reset (категория: constant)
readonly COLOR_RESET=$'\033[0m'
# @global COLOR_BLACK — ANSI color escape: black (category: constant)
# @global COLOR_BLACK — ANSI-escape цвета: black (категория: constant)
readonly COLOR_BLACK=$'\033[0;30m'
# @global COLOR_RED — ANSI color escape: red (category: constant)
# @global COLOR_RED — ANSI-escape цвета: red (категория: constant)
readonly COLOR_RED=$'\033[0;31m'
# @global COLOR_GREEN — ANSI color escape: green (category: constant)
# @global COLOR_GREEN — ANSI-escape цвета: green (категория: constant)
readonly COLOR_GREEN=$'\033[0;32m'
# @global COLOR_YELLOW — ANSI color escape: yellow (category: constant)
# @global COLOR_YELLOW — ANSI-escape цвета: yellow (категория: constant)
readonly COLOR_YELLOW=$'\033[0;33m'
# @global COLOR_BLUE — ANSI color escape: blue (category: constant)
# @global COLOR_BLUE — ANSI-escape цвета: blue (категория: constant)
readonly COLOR_BLUE=$'\033[0;34m'
# @global COLOR_PURPLE — ANSI color escape: purple (category: constant)
# @global COLOR_PURPLE — ANSI-escape цвета: purple (категория: constant)
readonly COLOR_PURPLE=$'\033[0;35m'
# @global COLOR_CYAN — ANSI color escape: cyan (category: constant)
# @global COLOR_CYAN — ANSI-escape цвета: cyan (категория: constant)
readonly COLOR_CYAN=$'\033[0;36m'
# @global COLOR_WHITE — ANSI color escape: white (category: constant)
# @global COLOR_WHITE — ANSI-escape цвета: white (категория: constant)
readonly COLOR_WHITE=$'\033[0;37m'

# @global COLOR_BRIGHT_BLACK — ANSI color escape: bright_black (category: constant)
# @global COLOR_BRIGHT_BLACK — ANSI-escape цвета: bright_black (категория: constant)
readonly COLOR_BRIGHT_BLACK=$'\033[0;90m'
# @global COLOR_BRIGHT_RED — ANSI color escape: bright_red (category: constant)
# @global COLOR_BRIGHT_RED — ANSI-escape цвета: bright_red (категория: constant)
readonly COLOR_BRIGHT_RED=$'\033[0;91m'
# @global COLOR_BRIGHT_GREEN — ANSI color escape: bright_green (category: constant)
# @global COLOR_BRIGHT_GREEN — ANSI-escape цвета: bright_green (категория: constant)
readonly COLOR_BRIGHT_GREEN=$'\033[0;92m'
# @global COLOR_BRIGHT_YELLOW — ANSI color escape: bright_yellow (category: constant)
# @global COLOR_BRIGHT_YELLOW — ANSI-escape цвета: bright_yellow (категория: constant)
readonly COLOR_BRIGHT_YELLOW=$'\033[0;93m'
# @global COLOR_BRIGHT_BLUE — ANSI color escape: bright_blue (category: constant)
# @global COLOR_BRIGHT_BLUE — ANSI-escape цвета: bright_blue (категория: constant)
readonly COLOR_BRIGHT_BLUE=$'\033[0;94m'
# @global COLOR_BRIGHT_PURPLE — ANSI color escape: bright_purple (category: constant)
# @global COLOR_BRIGHT_PURPLE — ANSI-escape цвета: bright_purple (категория: constant)
readonly COLOR_BRIGHT_PURPLE=$'\033[0;95m'
# @global COLOR_BRIGHT_CYAN — ANSI color escape: bright_cyan (category: constant)
# @global COLOR_BRIGHT_CYAN — ANSI-escape цвета: bright_cyan (категория: constant)
readonly COLOR_BRIGHT_CYAN=$'\033[0;96m'
# @global COLOR_BRIGHT_WHITE — ANSI color escape: bright_white (category: constant)
# @global COLOR_BRIGHT_WHITE — ANSI-escape цвета: bright_white (категория: constant)
readonly COLOR_BRIGHT_WHITE=$'\033[0;97m'

# 
# Константы для форматирования / Formatting constants
# 

# @global SPINNER_CHARS — Spinner animation characters (category: constant)
# @global SPINNER_CHARS — Символы анимации спиннера (категория: constant)
readonly SPINNER_CHARS='/-\|'
# @global PROGRESS_BLOCK — Progress bar fill character (category: constant)
# @global PROGRESS_BLOCK — Символ заполнения прогресс-бара (категория: constant)
readonly PROGRESS_BLOCK='█'
# @global PROGRESS_EMPTY — Progress bar empty character (category: constant)
# @global PROGRESS_EMPTY — Символ пустоты прогресс-бара (категория: constant)
readonly PROGRESS_EMPTY=' '

# 
# Константы для системных путей / System path constants
# 

# @global SYS_ETC — Standard system path (category: constant)
# @global SYS_ETC — Стандартный системный путь (категория: constant)
readonly SYS_ETC="/etc"
# @global SYS_VAR — Standard system path (category: constant)
# @global SYS_VAR — Стандартный системный путь (категория: constant)
readonly SYS_VAR="/var"
# @global SYS_TMP — Standard system path (category: constant)
# @global SYS_TMP — Стандартный системный путь (категория: constant)
readonly SYS_TMP="/tmp"
# @global SYS_USR_LOCAL — Standard system path (category: constant)
# @global SYS_USR_LOCAL — Стандартный системный путь (категория: constant)
readonly SYS_USR_LOCAL="/usr/local"
# @global SYS_HOME — Standard system path (category: constant)
# @global SYS_HOME — Стандартный системный путь (категория: constant)
readonly SYS_HOME="${HOME}"

# 
# Массивы констант для валидации / Constant arrays for validation
# 

# @global SUPPORTED_DISTROS — Distributions supported by default (category: constant)
# @global SUPPORTED_DISTROS — Дистрибутивы, поддерживаемые по умолчанию (категория: constant)
readonly SUPPORTED_DISTROS=("alma" "centos" "rhel" "fedora" "debian" "ubuntu")

# @global FILENAME_ALLOWED_CHARS — Regex of characters allowed in filenames (category: constant)
# @global FILENAME_ALLOWED_CHARS — Регэксп разрешённых символов имён файлов (категория: constant)
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