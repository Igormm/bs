#!/usr/bin/env bash
#
# core/logger.sh — модуль логирования фреймворка BS
# core/logger.sh — BS framework logging module
#
# Предоставляет гибкую систему логирования с уровнями, цветами и форматированием.
# Provides flexible logging system with levels, colors and formatting.
#
# Использование / Usage:
#   log::print "сообщение"           # Алиас для log::info / Alias for log::info
#   log::info "информация"           # Информационное сообщение / Information message
#   log::warn "предупреждение"       # Предупреждение / Warning
#   log::error "ошибка"              # Сообщение об ошибке / Error message
#   log::debug "отладка"             # Отладочное сообщение / Debug message
#   log::success "успех"             # Сообщение об успехе / Success message
#   log::trace "трассировка"         # Трассировочное сообщение / Trace message
#
# Настройка через переменные окружения / Configuration via environment variables:
# BS_LOG_LEVEL=TRACE|DEBUG|INFO|WARN|ERROR|SUCCESS|NONE (по умолчанию INFO / default:
# INFO)
# BS_LOG_COLOR=auto|always|never (по умолчанию auto / default: auto)
# BS_LOG_FORMAT=text|json|structured (по умолчанию text / default: text)
# BS_LOG_TIMESTAMP=true|false (по умолчанию true / default: true)
#

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Core prerequisites
source "$(dirname -- "${BASH_SOURCE[0]}")/prereq.sh"
bs::guard "LOGGER" || return 0

# Настройки по умолчанию / Default settings
: "${BS_LOG_LEVEL:=INFO}"
: "${BS_LOG_COLOR:=auto}"
: "${BS_LOG_FORMAT:=text}"
: "${BS_LOG_TIMESTAMP:=true}"

# ==========================================
# Приватные вспомогательные функции / Private helper functions
# ==========================================

# @private
# @description Получить текущую временную метку / Get current timestamp
# @return Timestamp in format YYYY-MM-DD HH:MM:SS / Метка времени в формате ГГГГ-ММ-ДД
# ЧЧ:ММ:СС
log::__timestamp() {
    if [[ "${BS_LOG_TIMESTAMP}" == "true" ]]; then
        date +"%Y-%m-%d %H:%M:%S"
    fi
}

# @private
# @description Проверить, разрешены ли цвета в терминале / Check if colors are enabled in
# terminal
# @return 0 if colors enabled, 1 otherwise / 0 если цвета разрешены, иначе 1
log::__is_color_enabled() {
    case "${BS_LOG_COLOR}" in
        always)
            return 0
            ;;
        never)
            return 1
            ;;
        auto|*)
            # Цвета разрешены только в интерактивном терминале
            # Colors only enabled in interactive terminal
            [[ -t 1 ]] && return 0 || return 1
            ;;
    esac
}

# @private
# @description Преобразовать уровень логирования в число для сравнения
# @description Convert log level to number for comparison
# @param $1 Log level string / Строка уровня логирования
# @return Numeric level / Числовой уровень
log::__level_to_number() {
    local -r level="${1^^}"

    case "${level}" in
        TRACE)    printf '%d\n' 0 ;;
        DEBUG)    printf '%d\n' 10 ;;
        INFO)     printf '%d\n' 20 ;;
        SUCCESS)  printf '%d\n' 25 ;;
        WARN)     printf '%d\n' 30 ;;
        ERROR)    printf '%d\n' 40 ;;
        FATAL)    printf '%d\n' 50 ;;
        NONE)     printf '%d\n' 1000 ;;
        *)        printf '%d\n' 20 ;;  # По умолчанию INFO / Default to INFO
    esac
}

# @private
# @description Проверить, разрешен ли вывод сообщения данного уровня
# @description Check if message of this level is allowed to be output
# @param $1 Message level / Уровень сообщения
# @return 0 if allowed, 1 otherwise / 0 если разрешено, иначе 1
log::__is_level_allowed() {
    local msg_level="${1^^}"
    local msg_num cfg_num
    
    msg_num="$(log::__level_to_number "${msg_level}")"
    cfg_num="$(log::__level_to_number "${BS_LOG_LEVEL}")"
    
    [[ "${msg_num}" -ge "${cfg_num}" ]]
}

# @private
# @description Получить цвет для уровня логирования
# @description Get color for log level
# @param $1 Log level / Уровень логирования
# @return ANSI color code / ANSI код цвета
log::__get_level_color() {
    local -r level="${1^^}"

    case "${level}" in
        TRACE)   printf '%s\n' '\033[90m' ;;     # Серый / Gray
        DEBUG)   printf '%s\n' '\033[36m' ;;     # Циан / Cyan
        INFO)    printf '%s\n' '\033[34m' ;;     # Синий / Blue
        SUCCESS) printf '%s\n' '\033[32m' ;;     # Зеленый / Green
        WARN)    printf '%s\n' '\033[33m' ;;     # Желтый / Yellow
        ERROR)   printf '%s\n' '\033[31m' ;;     # Красный / Red
        FATAL)   printf '%s\n' '\033[35m' ;;     # Пурпурный / Purple
        *)       printf '%s\n' '\033[0m' ;;      # Сброс / Reset
    esac
}

# @private
# @description Экранировать строку для вставки в JSON
# @description Escape string for embedding into JSON
# @param $1 Raw string / Исходная строка
# @return Escaped string / Экранированная строка
log::__json_escape() {
    local s="${1}"
    s="${s//\\/\\\\}"      # Обратный слэш / Backslash
    s="${s//\"/\\\"}"      # Кавычка / Quote
    s="${s//$'\n'/\\n}"    # Перевод строки / Newline
    s="${s//$'\r'/\\r}"    # Возврат каретки / Carriage return
    s="${s//$'\t'/\\t}"    # Табуляция / Tab
    printf '%s' "${s}"
}

# @private
# @description Форматировать сообщение для вывода
# @description Format message for output
# @param $1 Log level / Уровень логирования
# @param $@ Message text / Текст сообщения
# @return Formatted message / Отформатированное сообщение
log::__format_message() {
    local -r level="${1^^}"
    shift
    local text="$*"
    
    local timestamp
    timestamp="$(log::__timestamp)"
    
    case "${BS_LOG_FORMAT}" in
        json)
            # JSON формат / JSON format
            local escaped_text
            escaped_text="$(log::__json_escape "${text}")"
            if [[ -n "$timestamp" ]]; then
                printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
                    "$timestamp" "$level" "$escaped_text"
            else
                printf '{"level":"%s","message":"%s"}\n' "$level" "$escaped_text"
            fi
            ;;
        structured)
            # Структурированный формат / Structured format
            if [[ -n "$timestamp" ]]; then
                printf '[%s] %-5s | %s\n' "$timestamp" "$level" "$text"
            else
                printf '[%-5s] %s\n' "$level" "$text"
            fi
            ;;
        text|*)
            # Текстовый формат с цветами / Text format with colors
            if log::__is_color_enabled; then
                local -r color_reset='\033[0m'
                local color="$(log::__get_level_color "$level")"
                local -r bold='\033[1m'
                
                # Для ошибок и фатальных используем жирный шрифт
                # For errors and fatal use bold
                if [[ "$level" == "ERROR" ]] || [[ "$level" == "FATAL" ]]; then
                    color="${color}${bold}"
                fi
                
                if [[ -n "$timestamp" ]]; then
                    printf '%s[%s]%s %s%-5s%s %s\n' \
                        '\033[90m' "$timestamp" "$color_reset" \
                        "$color" "$level" "$color_reset" \
                        "$text"
                else
                    printf '%s%-5s%s %s\n' \
                        "$color" "$level" "$color_reset" \
                        "$text"
                fi
            else
                # Текстовый формат без цветов / Text format without colors
                if [[ -n "$timestamp" ]]; then
                    printf '[%s] %-5s %s\n' "$timestamp" "$level" "$text"
                else
                    printf '[%-5s] %s\n' "$level" "$text"
                fi
            fi
            ;;
    esac
}

# ==========================================
# Публичные функции логирования / Public logging functions
# ==========================================

# @description Вывести сообщение уровня TRACE / Output TRACE level message
# @param $@ Message text / Текст сообщения
# @example
#   log::trace "Entering function with args: $@"
log::trace() {
    log::__is_level_allowed "TRACE" || return 0
    log::__format_message "TRACE" "$@"
}

# @description Вывести сообщение уровня DEBUG / Output DEBUG level message
# @param $@ Message text / Текст сообщения
# @example
#   log::debug "Processing item: $item"
log::debug() {
    log::__is_level_allowed "DEBUG" || return 0
    log::__format_message "DEBUG" "$@"
}

# @description Вывести информационное сообщение / Output INFO level message
# @param $@ Message text / Текст сообщения
# @example
#   log::info "Starting process with PID: $$"
log::info() {
    log::__is_level_allowed "INFO" || return 0
    log::__format_message "INFO" "$@"
}

# @description Вывести сообщение об успехе / Output SUCCESS level message
# @param $@ Message text / Текст сообщения
# @example
#   log::success "Operation completed successfully"
log::success() {
    log::__is_level_allowed "SUCCESS" || return 0
    log::__format_message "SUCCESS" "$@"
}

# @description Вывести предупреждение / Output WARN level message
# @param $@ Message text / Текст сообщения
# @example
#   log::warn "Configuration file not found, using defaults"
log::warn() {
    log::__is_level_allowed "WARN" || return 0
    log::__format_message "WARN" "$@" >&2
}

# @description Вывести сообщение об ошибке / Output ERROR level message
# @param $@ Message text / Текст сообщения
# @example
#   log::error "Failed to connect to database: $error"
log::error() {
    log::__is_level_allowed "ERROR" || return 0
    log::__format_message "ERROR" "$@" >&2
}

# @description Вывести фатальное сообщение и вернуть код ошибки
# @description Output FATAL level message and return error code
# @param $@ Message text / Текст сообщения
# @return E_ERROR (или 1, если const.sh не загружен) / E_ERROR (or 1 if const.sh not
# loaded)
# @example
#   log::fatal "Critical error, cannot continue" || exit 1
log::fatal() {
    if log::__is_level_allowed "FATAL"; then
        log::__format_message "FATAL" "$@" >&2
    fi
    
    # Библиотечная функция не завершает чужой скрипт: возвращаем код,
    # решение о выходе остаётся за вызывающим
    # Library function must not exit the caller's script: return a code,
    # the decision to exit is up to the caller
    return "${E_ERROR:-1}"
}

# @description Алиас для log::info для обратной совместимости
# @description Alias for log::info for backward compatibility
# @param $@ Message text / Текст сообщения
# @example
#   log::print "Simple message"
log::print() {
    log::info "$@"
}

# @description Вывести заголовок / Output header
# @param $1 Header text / Текст заголовка
# @param $2 Character for underline (optional, default: "=") / Символ подчеркивания
# (опционально, по умолчанию: "=")
# @example
#   log::header "Starting deployment"
log::header() {
    local text="${1:?Missing header text}"
    local char="${2:-=}"
    local line
    
    # Создаем линию подчеркивания / Create underline
    printf -v line '%*s' "${#text}" ''
    line="${line// /$char}"
    
    log::info ""
    log::info "$text"
    log::info "$line"
    log::info ""
}

# @description Вывести список с маркерами / Output bulleted list
# @param $@ List items / Элементы списка
# @example
#   log::list "Item 1" "Item 2" "Item 3"
log::list() {
    local item
    for item in "$@"; do
        if log::__is_color_enabled; then
            log::info "  • $item"
        else
            log::info "  * $item"
        fi
    done
}

# @description Вывести таблицу / Output table
# @param $1...$n Table rows as "col1|col2|col3" / Строки таблицы как "кол1|кол2|кол3"
# @example
#   log::table "Name|Value" "----|-----" "Host|localhost" "Port|8080"
log::table() {
    local row
    local -a rows=("$@")
    
    for row in "${rows[@]}"; do
        log::info "  $row"
    done
}

# @description Вывести прогресс бар / Output progress bar
# @param $1 Current value / Текущее значение
# @param $2 Maximum value / Максимальное значение
# @param $3 Width of progress bar (optional, default: 50) / Ширина прогресс-бара
# (опционально, по умолчанию: 50)
# @example
#   log::progress 25 100
log::progress() {
    local current="${1:?Missing current value}"
    local max="${2:?Missing max value}"
    local width="${3:-50}"
    
    local percentage=$(( current * 100 / max ))
    local filled=$(( width * current / max ))
    local empty=$(( width - filled ))
    
    local bar
    printf -v bar '%*s' "$filled" ''
    bar="${bar// /█}"
    
    local empty_bar
    printf -v empty_bar '%*s' "$empty" ''
    
    printf '\r  [%s%s] %d%%' "$bar" "$empty_bar" "$percentage"
    
    if [[ $current -eq $max ]]; then
        echo  # Новая строка при завершении / New line when done
    fi
}

# @description Очистить текущую строку в терминале
# @description Clear current line in terminal
# @example
#   log::clear_line
log::clear_line() {
    printf '\r\033[K'
}

# ==========================================
# Инициализация модуля / Module initialization
# ==========================================

# Проверяем доступность core/const.sh / Check if core/const.sh is available
if [[ -z "${E_SUCCESS:-}" ]]; then
    echo "logger: warning: core/const.sh not loaded, using default constants" >&2
    readonly E_SUCCESS=0
    readonly E_ERROR=1
fi

# Отмечаем модуль как загруженный / Mark module as loaded
declare -g LOGGER_LOADED="1"

log::debug "Logger module initialized with level: ${BS_LOG_LEVEL}, color: ${BS_LOG_COLOR}" 2>/dev/null || true
