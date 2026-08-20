#!/usr/bin/env bash
#
#
#

# core/utils.sh
# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs::guard "UTILS" || return 0


# Устанавливает строгий режим.
# @function utils::strict
utils::strict() {
  set -euo pipefail
  IFS=$'\n\t'
}

# Проверяет, был ли уже загружен модуль.
# Возвращает 0 – если уже загружён (нужно прервать выполнение модуля),
#            1 – если ещё не загружен (можно продолжать).
# Использование:
#   if utils::guard "foo"; then return 0; fi
#   readonly __FOO_SOURCED=1
# @function utils::guard
# @deprecated Используйте bs::guard из core/prereq.sh — она и проверяет, и ставит метку
# @param $1 {string} Уникальное имя модуля (без __ и _SOURCED)
# @returns 0  модуль уже загружался
# @returns 1  модуль ещё не загружался
utils::guard() {
  local -r module="${1:?Module name required}"
  bs::guard_loaded "${module}"
}

# Проверяет наличие команды в PATH.
# Заменяет идиому: command -v foo >/dev/null 2>&1
# @function utils::has
# @param $1 {string} Имя команды
# @returns 0  команда доступна
# @returns 1  команда не найдена
# @example
#   if utils::has dnf; then ...; fi
utils::has() {
  local -r cmd="${1}"
  command -v "${cmd}" >/dev/null 2>&1
}

# Выполняет команду, полностью подавляя вывод. Код возврата сохраняется.
# Заменяет идиому: cmd >/dev/null 2>&1
# @function utils::quiet
# @param $@ {string} Команда и её аргументы
# @returns код возврата команды
# @example
#   if utils::quiet grep -q foo file; then ...; fi
utils::quiet() {
  "$@" >/dev/null 2>&1
}

# Выполняет команду, подавляя только stderr. Код возврата сохраняется.
# Заменяет идиому: cmd 2>/dev/null
# @function utils::quiet_err
# @param $@ {string} Команда и её аргументы
# @returns код возврата команды
utils::quiet_err() {
  "$@" 2>/dev/null
}

# Выполняет команду, подавляя вывод и игнорируя результат.
# Явная замена идиомы: cmd >/dev/null 2>&1 || true
# Использовать только там, где неудача команды действительно не важна.
# @function utils::ignore
# @param $@ {string} Команда и её аргументы
# @returns всегда 0
utils::ignore() {
  "$@" >/dev/null 2>&1 || :
}

# Выполняет команду, игнорируя результат; stderr подавляется, stdout сохраняется.
# Явная замена идиомы: cmd 2>/dev/null || true (и utils::quiet_err cmd || true)
# Использовать для best-effort операций, где неудача допустима.
# @function utils::attempt
# @param $@ {string} Команда и её аргументы
# @returns всегда 0
utils::attempt() {
  "$@" 2>/dev/null || :
}

# Текущее время в секундах (epoch).
# Заменяет идиому: date +%s
# @function utils::now_s
# @stdout секунды с начала эпохи
utils::now_s() {
  date +%s
}

# Текущее время в миллисекундах (epoch).
# Заменяет идиому: date +%s%3N
# @function utils::now_ms
# @stdout миллисекунды с начала эпохи
utils::now_ms() {
  date +%s%3N
}

# Текущее время в секундах с дробной частью (для интервалов через bc/awk).
# Заменяет идиому: date +%s.%N
# @function utils::now_float
# @stdout секунды с наносекундной дробной частью
utils::now_float() {
  date +%s.%N
}

# Метка времени для имён файлов: YYYYMMDD_HHMMSS.
# Заменяет идиому: date +%Y%m%d_%H%M%S
# @function utils::stamp
# @stdout timestamp, безопасный для имён файлов
utils::stamp() {
  date +%Y%m%d_%H%M%S
}

# Человекочитаемая метка времени для логов: "YYYY-MM-DD HH:MM:SS".
# Заменяет идиому: date '+%Y-%m-%d %H:%M:%S'
# @function utils::log_stamp
# @stdout timestamp для логов
utils::log_stamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

# Разбивает строку на массив по заданному разделителю.
# Безопасна при любом IFS вызывающего: устанавливает локальный IFS внутри функции.
# @function utils::split
# @param $1 {string} Имя выходного массива
# @param $2 {string} Исходная строка
# @param $3 {string} Разделитель (по умолчанию пробел)
# @example
#   utils::split my_array "a b c"
#   utils::split my_array "one,two,three" ","
utils::split() {
  local -n __utils_split_ref="${1:?Array variable name required}"
  local str="${2:-}"
  local delim="${3:- }"

  local IFS="${delim}"
  # Пустая строка даёт пустой массив, а не массив из одной пустой строки
  if is::empty "${str}"; then
    __utils_split_ref=()
    return 0
  fi

  read -ra __utils_split_ref <<< "${str}"
}

# Проверяет существование файла-источника, загружает его и убеждается,
# что требуемая функция появилась в окружении.
# Возвращает 0 при успехе, 1 при любой ошибке.
# Глобальные переменные не изменяются.
#
# Аргументы:
#   $1  путь до файла (обязательный)
#   $2  имя проверяемой функции (обязательный)
# Вывод:
#   Всё диагностическое пишет в STDERR
# Load target file and confirm required function exists.
#
# @function utils::ensure_source
# @param $1 {string} Absolute or relative path to file (must exist)
# @param $2 {string} Function name to check after sourcing
# @returns 0  If file loaded and function present
# @returns 1  Missing file, failed source, or function absent
# @stderr   Diagnostic messages
# @example
#   utils::ensure_source "${ROOT_DIR}/lib/math.sh" add_integers
utils::ensure_source() {
  local -r file="${1:?File path is required}"
  local -r func="${2:?Function name is required}"

  #  валидация аргументов 
  is::not_empty ${file} || { log::error "file argument is empty"; return "${E_INVALID:-2}"; }
  is::not_empty ${func} || { log::error "function argument is empty"; return "${E_INVALID:-2}"; }

  if ! is::file "${file}"; then
    log::error "file not found: ${file}"
    return "${E_ERROR:-1}"
  fi

  if ! source -- "${file}"; then
    log::error "failed to source file: ${file}"
    return "${E_ERROR:-1}"
  fi

  if ! declare -F -- "${func}" >/dev/null 2>&1; then
    log::error "required function ${func} not defined"
    return "${E_ERROR:-1}"
  fi

  return 0
}

# Function to check if current shell is at least the required version
utils::ensure_shell_version() {
    local -r required_version="${1:-4}"  # Default to version 4 if not specified

    if is::empty "${SHELL:-}"; then
        log::error "SHELL variable is not set, cannot verify shell version"
        return "${E_ERROR:-1}"
    fi
    local -r shell_name="$(basename "$SHELL")"

    case "${shell_name}" in
        "bash")
            if is::empty "${BASH_VERSION:-}" || [[ "${BASH_VERSION%%.*}" -lt "${required_version}" ]]; then
                log::error "Bash version ${required_version} or higher is required but you have version ${BASH_VERSION:-unknown}"
                return "${E_ERROR:-1}"
            fi
            ;;
        "zsh")
            if is::empty "${ZSH_VERSION:-}" || [[ "${ZSH_VERSION%%.*}" -lt "${required_version}" ]]; then
                log::error "Zsh version ${required_version} or higher is required but you have version ${ZSH_VERSION:-unknown}"
                return "${E_ERROR:-1}"
            fi
            ;;
        *)
            log::warn "Unknown shell ${shell_name}, cannot verify version requirements"
            return "${E_ERROR:-1}"
            ;;
    esac

    printf 'Shell %s meets version requirement (>= %s)\n' "${shell_name}" "${required_version}"
    return 0
}

## @brief Получение корневой директории фреймворка
## @description Определяет путь независимо от способа вызова
## @global Устанавливает FRAMEWORK_ROOT
utils::detect_root() {
    local script_source
    
    # 1. Пробуем получить из переменной окружения
    if is::not_empty "${FRAMEWORK_ROOT:-}" && is::dir "${FRAMEWORK_ROOT}"; then
        # log:: опционален для utils (нижний уровень) / log:: is optional for utils
        if declare -F log::debug >/dev/null 2>&1; then
            log::debug "FRAMEWORK_ROOT задан явно: ${FRAMEWORK_ROOT}"
        fi
        return 0
    fi
    
    # 2. Определяем путь к скрипту
    if [[ "${BASH_SOURCE[0]+x}" == "x" ]]; then
        script_source="${BASH_SOURCE[0]}"
    else
        script_source="$0"
    fi
    
    # 3. Обработка симлинков
    if is::symlink "${script_source}"; then
        script_source="$(readlink -f -- "${script_source}")"
    fi
    
    # 4. Безопасное получение директории
    local script_dir
    script_dir="$(dirname -- "${script_source}")"
    
    # 5. Переход на уровень выше (если скрипт в bin/)
    if [[ "$(basename -- "${script_dir}")" == "bin" ]]; then
        script_dir="$(dirname -- "${script_dir}")"
    fi
    
    # 6. Абсолютный путь
    FRAMEWORK_ROOT="$(cd -- "${script_dir}" && pwd -P)"
    export FRAMEWORK_ROOT
    
    # log:: опционален для utils (нижний уровень) / log:: is optional for utils
    if declare -F log::info >/dev/null 2>&1; then
        log::info "Корень фреймворка: ${FRAMEWORK_ROOT}"
    fi
    return 0
}

#bootdir
# @description Определить каталог bootstrap/ фреймворка / Detect framework bootstrap/ dir
# @global Устанавливает и экспортирует BOOT_DIR / Sets and exports BOOT_DIR
utils::boot_dir() {
  BOOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../bootstrap" &>/dev/null && pwd)"
  export BOOT_DIR
}

