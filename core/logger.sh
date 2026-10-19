#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, printf, подстановки параметров и $(( )) без local, массивов, ${1^^}, printf -v и $'..'; ширина рамки log::header считается ${#} (в dash/ash — байты) / valid POSIX sh: case, printf, parameter expansion and $(( )) with no local, arrays, ${1^^}, printf -v or $'..'; the width of the log::header frame is ${#} (bytes in dash/ash)
# @tier core — builtins and date; works everywhere
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

# ИМЕНА / NAMES
#   Real functions: bs_log_trace, bs_log_debug, bs_log_info, bs_log_success, bs_log_warn, bs_log_error, bs_log_fatal,
#   bs_log_print, bs_log_header, bs_log_list, bs_log_table, bs_log_progress, bs_log_clear_line and the private
#   bs_log_timestamp, bs_log_is_color_enabled, bs_log_level_to_number, bs_log_is_level_allowed,
#   bs_log_get_level_color, bs_log_json_escape, bs_log_format_message; in bash and zsh also log::*
#   (the old names, used by the whole framework) and log::__* for the private ones.
#   Настоящие функции: bs_log_trace … bs_log_clear_line и приватные bs_log_timestamp …
#   bs_log_format_message; в bash и zsh — ещё и log::* (прежние имена, их зовёт весь фреймворк)
#   и log::__* для приватных.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard LOGGER || return 0

# Dependencies / Зависимости
bs_source_relative "const.sh"

# @global BS_LOG_LEVEL — Env: log level (DEBUG/INFO/WARN/ERROR) (category: env)
# @global BS_LOG_LEVEL — Env: уровень логирования (DEBUG/INFO/WARN/ERROR) (категория: env)
: "${BS_LOG_LEVEL:=INFO}"
# @global BS_LOG_COLOR — Env: log color mode: auto/always/never (category: env)
# @global BS_LOG_COLOR — Env: режим цвета лога: auto/always/never (категория: env)
: "${BS_LOG_COLOR:=auto}"
# @global BS_LOG_FORMAT — Env: log format: text/raw (category: env)
# @global BS_LOG_FORMAT — Env: формат лога: text/raw (категория: env)
: "${BS_LOG_FORMAT:=text}"
# @global BS_LOG_TIMESTAMP — Env: log timestamp: true/false (category: env)
# @global BS_LOG_TIMESTAMP — Env: временная метка в логе: true/false (категория: env)
: "${BS_LOG_TIMESTAMP:=true}"

# Байт ESC из printf: без $'\033', которого нет в POSIX sh / the ESC byte from printf: no $'\033', it is not POSIX sh
__bs_log_esc=$(printf '\033')

# ==========================================
# Приватные вспомогательные функции / Private helper functions
# ==========================================

# @private
# @description Получить текущую временную метку / Get current timestamp
# @return Timestamp in format YYYY-MM-DD HH:MM:SS / Метка времени в формате ГГГГ-ММ-ДД ЧЧ:ММ:СС
bs_log_timestamp() {
  if [ "${BS_LOG_TIMESTAMP}" = "true" ]; then
    date +"%Y-%m-%d %H:%M:%S"
  fi
}

# @private
# @description Проверить, включён ли цвет для дескриптора / Check whether colour is on for a descriptor
# @param $1 file descriptor, default 1 / дескриптор, по умолчанию 1
bs_log_is_color_enabled() {
  if [ -n "${NO_COLOR:-}" ]; then
    return 1
  fi
  case "${BS_LOG_COLOR}" in
    always) return 0 ;;
    never) return 1 ;;
    *)
      if [ -t "${1:-1}" ]; then return 0; fi
      return 1 ;;
  esac
}

# @private
# @description Числовой приоритет уровня (регистр не важен) / Numeric priority of a level (case-insensitive)
# @param $1 level / уровень
bs_log_level_to_number() {
  case "${1:-}" in
    [Tt][Rr][Aa][Cc][Ee])             printf '%d\n' 0 ;;
    [Dd][Ee][Bb][Uu][Gg])             printf '%d\n' 10 ;;
    [Ii][Nn][Ff][Oo])                 printf '%d\n' 20 ;;
    [Ss][Uu][Cc][Cc][Ee][Ss][Ss])     printf '%d\n' 25 ;;
    [Ww][Aa][Rr][Nn])                 printf '%d\n' 30 ;;
    [Ee][Rr][Rr][Oo][Rr])             printf '%d\n' 40 ;;
    [Ff][Aa][Tt][Aa][Ll])             printf '%d\n' 50 ;;
    [Nn][Oo][Nn][Ee])                 printf '%d\n' 1000 ;;
    *)                                printf '%d\n' 20 ;;  # По умолчанию INFO / Default to INFO
  esac
}

# @private
# @description Разрешён ли вывод сообщения этого уровня / Whether a message of this level is printed
# @param $1 level / уровень
bs_log_is_level_allowed() {
  __bs_log_msg_num=$(bs_log_level_to_number "${1:-}")
  __bs_log_cfg_num=$(bs_log_level_to_number "${BS_LOG_LEVEL}")
  [ "$__bs_log_msg_num" -ge "$__bs_log_cfg_num" ]
}

# @private
# @description ANSI-цвет уровня (уровень — заглавными) / ANSI colour of a level (upper-case level)
# @param $1 level / уровень
bs_log_get_level_color() {
  case "${1:-}" in
    TRACE)   printf '%s\n' "${__bs_log_esc}[90m" ;;   # Серый / Gray
    DEBUG)   printf '%s\n' "${__bs_log_esc}[36m" ;;   # Циан / Cyan
    INFO)    printf '%s\n' "${__bs_log_esc}[34m" ;;   # Синий / Blue
    SUCCESS) printf '%s\n' "${__bs_log_esc}[32m" ;;   # Зеленый / Green
    WARN)    printf '%s\n' "${__bs_log_esc}[33m" ;;   # Желтый / Yellow
    ERROR)   printf '%s\n' "${__bs_log_esc}[31m" ;;   # Красный / Red
    FATAL)   printf '%s\n' "${__bs_log_esc}[35m" ;;   # Пурпурный / Purple
    *)       printf '%s\n' "${__bs_log_esc}[0m" ;;    # Сброс / Reset
  esac
}

# @private
# @description Заменить все вхождения $2 на $3 в $1; результат в __bs_log_out / Replace every $2 with $3 in $1; the result is in __bs_log_out
# (подстановка ${s//a/b} есть не везде / the ${s//a/b} substitution does not exist everywhere)
bs_log_replace_all() {
  __bs_log_rs=$1
  __bs_log_out=''
  while :; do
    case "$__bs_log_rs" in
      *"$2"*)
        __bs_log_out="${__bs_log_out}${__bs_log_rs%%"$2"*}$3"
        __bs_log_rs=${__bs_log_rs#*"$2"} ;;
      *)
        __bs_log_out="${__bs_log_out}${__bs_log_rs}"
        break ;;
    esac
  done
}

# @private
# @description Экранирование строки для JSON / Escape a string for JSON
# @param $1 text / текст
bs_log_json_escape() {
  __bs_log_js=$1
  # shellcheck disable=SC1003  # '\' — один обратный слэш в одинарных кавычках / '\' is one backslash in single quotes
  bs_log_replace_all "$__bs_log_js" '\' '\\'; __bs_log_js=$__bs_log_out   # Обратный слэш / Backslash
  bs_log_replace_all "$__bs_log_js" '"' '\"';   __bs_log_js=$__bs_log_out   # Кавычка / Quote
  bs_log_replace_all "$__bs_log_js" '
' '\n';                                       __bs_log_js=$__bs_log_out   # Перевод строки / Newline
  bs_log_replace_all "$__bs_log_js" "$(printf '\r')" '\r'; __bs_log_js=$__bs_log_out   # Возврат каретки / Carriage return
  bs_log_replace_all "$__bs_log_js" "$(printf '\t')" '\t'; __bs_log_js=$__bs_log_out   # Табуляция / Tab
  printf '%s' "$__bs_log_js"
}

# @private
# @description Форматировать и напечатать сообщение / Format and print a message
# @param $1 level (upper-case) / уровень (заглавными)
# @param $2 file descriptor / дескриптор
# @param $@ message words / слова сообщения
bs_log_format_message() {
  __bs_log_level=${1:-INFO}
  __bs_log_fd=${2:-1}
  shift 2
  # слова склеиваются пробелом независимо от IFS вызывающего / words are joined with a space whatever the caller's IFS
  __bs_log_text=''
  __bs_log_first=1
  for __bs_log_word in "$@"; do
    if [ "$__bs_log_first" = 1 ]; then
      __bs_log_text=$__bs_log_word
      __bs_log_first=0
    else
      __bs_log_text="$__bs_log_text $__bs_log_word"
    fi
  done
  __bs_log_ts=$(bs_log_timestamp)
  case "${BS_LOG_FORMAT}" in
    json)
      __bs_log_esc_text=$(bs_log_json_escape "$__bs_log_text")
      if [ -n "$__bs_log_ts" ]; then
        printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
          "$__bs_log_ts" "$__bs_log_level" "$__bs_log_esc_text"
      else
        printf '{"level":"%s","message":"%s"}\n' "$__bs_log_level" "$__bs_log_esc_text"
      fi
      ;;
    structured)
      if [ -n "$__bs_log_ts" ]; then
        printf '[%s] %-5s | %s\n' "$__bs_log_ts" "$__bs_log_level" "$__bs_log_text"
      else
        printf '[%-5s] %s\n' "$__bs_log_level" "$__bs_log_text"
      fi
      ;;
    *)
      if bs_log_is_color_enabled "$__bs_log_fd"; then
        __bs_log_reset="${__bs_log_esc}[0m"
        __bs_log_color=$(bs_log_get_level_color "$__bs_log_level")
        if [ "$__bs_log_level" = "ERROR" ] || [ "$__bs_log_level" = "FATAL" ]; then
          __bs_log_color="${__bs_log_color}${__bs_log_esc}[1m"
        fi
        if [ -n "$__bs_log_ts" ]; then
          printf '%s[%s]%s %s%-5s%s %s\n' \
            "${__bs_log_esc}[90m" "$__bs_log_ts" "$__bs_log_reset" \
            "$__bs_log_color" "$__bs_log_level" "$__bs_log_reset" \
            "$__bs_log_text"
        else
          printf '%s%-5s%s %s\n' \
            "$__bs_log_color" "$__bs_log_level" "$__bs_log_reset" \
            "$__bs_log_text"
        fi
      else
        if [ -n "$__bs_log_ts" ]; then
          printf '[%s] %-5s %s\n' "$__bs_log_ts" "$__bs_log_level" "$__bs_log_text"
        else
          printf '[%-5s] %s\n' "$__bs_log_level" "$__bs_log_text"
        fi
      fi
      ;;
  esac
}

# ==========================================
# Публичный API / Public API
# ==========================================

# @description Трассировка / Trace message
# @param $@ message / сообщение
bs_log_trace() {
  bs_log_is_level_allowed "TRACE" || return 0
  bs_log_format_message "TRACE" 1 "$@"
}

# @description Отладка / Debug message
# @param $@ message / сообщение
bs_log_debug() {
  bs_log_is_level_allowed "DEBUG" || return 0
  bs_log_format_message "DEBUG" 1 "$@"
}

# @description Информация / Information message
# @param $@ message / сообщение
bs_log_info() {
  bs_log_is_level_allowed "INFO" || return 0
  bs_log_format_message "INFO" 1 "$@"
}

# @description Успех / Success message
# @param $@ message / сообщение
bs_log_success() {
  bs_log_is_level_allowed "SUCCESS" || return 0
  bs_log_format_message "SUCCESS" 1 "$@"
}

# @description Предупреждение (stderr) / Warning (stderr)
# @param $@ message / сообщение
bs_log_warn() {
  bs_log_is_level_allowed "WARN" || return 0
  bs_log_format_message "WARN" 2 "$@" >&2
}

# @description Ошибка (stderr) / Error (stderr)
# @param $@ message / сообщение
bs_log_error() {
  bs_log_is_level_allowed "ERROR" || return 0
  bs_log_format_message "ERROR" 2 "$@" >&2
}

# @description Фатальная ошибка (stderr), возвращает E_ERROR / Fatal error (stderr), returns E_ERROR
# @param $@ message / сообщение
bs_log_fatal() {
  if bs_log_is_level_allowed "FATAL"; then
    bs_log_format_message "FATAL" 2 "$@" >&2
  fi
  return "${E_ERROR:-1}"
}

# @description Алиас для bs_log_info / Alias for bs_log_info
# @param $@ message / сообщение
bs_log_print() {
  bs_log_info "$@"
}

# @description Заголовок (рамка или линия) / A header (a frame or a line)
# @param $1 text / текст
# @param $2 char: box (по умолчанию) или символ линии / box (default) or the line character
bs_log_header() {
  __bs_log_htext=${1:?Missing header text}
  __bs_log_hchar=${2:-box}
  if [ "$__bs_log_hchar" = "box" ]; then
    __bs_log_inner=" ${__bs_log_htext} "
    __bs_log_n=${#__bs_log_inner}
    __bs_log_line=''
    while [ "$__bs_log_n" -gt 0 ]; do
      __bs_log_line="${__bs_log_line}─"
      __bs_log_n=$((__bs_log_n - 1))
    done
    bs_log_info "╭${__bs_log_line}╮"
    bs_log_info "│${__bs_log_inner}│"
    bs_log_info "╰${__bs_log_line}╯"
    return 0
  fi
  __bs_log_n=${#__bs_log_htext}
  __bs_log_line=''
  while [ "$__bs_log_n" -gt 0 ]; do
    __bs_log_line="${__bs_log_line}${__bs_log_hchar}"
    __bs_log_n=$((__bs_log_n - 1))
  done
  bs_log_info ""
  bs_log_info "$__bs_log_htext"
  bs_log_info "$__bs_log_line"
  bs_log_info ""
}

# @description Маркированный список / A bulleted list
# @param $@ items / элементы
bs_log_list() {
  for __bs_log_item in "$@"; do
    if bs_log_is_color_enabled; then
      bs_log_info "  • $__bs_log_item"
    else
      bs_log_info "  * $__bs_log_item"
    fi
  done
}

# @description Таблица (строки с отступом) / A table (indented rows)
# @param $@ rows / строки
bs_log_table() {
  for __bs_log_row in "$@"; do
    bs_log_info "  $__bs_log_row"
  done
}

# @description Индикатор прогресса / A progress bar
# @param $1 current / текущее
# @param $2 max / максимум
# @param $3 width, default 50 / ширина, по умолчанию 50
bs_log_progress() {
  __bs_log_cur=${1:?Missing current value}
  __bs_log_max=${2:?Missing max value}
  __bs_log_width=${3:-50}
  [ "$__bs_log_max" -gt 0 ] || return "${E_ERROR:-1}"
  __bs_log_pct=$(( __bs_log_cur * 100 / __bs_log_max ))
  __bs_log_filled=$(( __bs_log_width * __bs_log_cur / __bs_log_max ))
  __bs_log_empty=$(( __bs_log_width - __bs_log_filled ))
  __bs_log_bar=''
  while [ "$__bs_log_filled" -gt 0 ]; do
    __bs_log_bar="${__bs_log_bar}█"
    __bs_log_filled=$((__bs_log_filled - 1))
  done
  __bs_log_ebar=''
  while [ "$__bs_log_empty" -gt 0 ]; do
    __bs_log_ebar="${__bs_log_ebar} "
    __bs_log_empty=$((__bs_log_empty - 1))
  done
  printf '\r  [%s%s] %d%%' "$__bs_log_bar" "$__bs_log_ebar" "$__bs_log_pct"
  if [ "$__bs_log_cur" -eq "$__bs_log_max" ]; then
    printf '\n'  # Новая строка при завершении / New line when done
  fi
}

# @description Очистить текущую строку / Clear the current line
bs_log_clear_line() {
  printf '\r\033[K'
}

# ==========================================
# Инициализация / Initialization
# ==========================================

# Резервные константы, если const.sh не загружен / Fallback constants if const.sh is not loaded
if [ -z "${E_SUCCESS:-}" ]; then
  printf '%s\n' "logger: warning: core/const.sh not loaded, using default constants" >&2
  bs_shell_readonly E_SUCCESS=0
  bs_shell_readonly E_ERROR=1
fi

# @global LOGGER_LOADED — Logger: loaded marker (category: module-flag)
# @global LOGGER_LOADED — Logger: маркер загрузки (категория: module-flag)
# shellcheck disable=SC2034  # читают тесты и другие модули / read by tests and other modules
LOGGER_LOADED="1"

bs_shell_alias bs_log_timestamp log::__timestamp
bs_shell_alias bs_log_is_color_enabled log::__is_color_enabled
bs_shell_alias bs_log_level_to_number log::__level_to_number
bs_shell_alias bs_log_is_level_allowed log::__is_level_allowed
bs_shell_alias bs_log_get_level_color log::__get_level_color
bs_shell_alias bs_log_json_escape log::__json_escape
bs_shell_alias bs_log_format_message log::__format_message
bs_shell_alias bs_log_trace log::trace
bs_shell_alias bs_log_debug log::debug
bs_shell_alias bs_log_info log::info
bs_shell_alias bs_log_success log::success
bs_shell_alias bs_log_warn log::warn
bs_shell_alias bs_log_error log::error
bs_shell_alias bs_log_fatal log::fatal
bs_shell_alias bs_log_print log::print
bs_shell_alias bs_log_header log::header
bs_shell_alias bs_log_list log::list
bs_shell_alias bs_log_table log::table
bs_shell_alias bs_log_progress log::progress
bs_shell_alias bs_log_clear_line log::clear_line

bs_log_debug "Logger module initialized with level: ${BS_LOG_LEVEL}, color: ${BS_LOG_COLOR}" 2>/dev/null || true
