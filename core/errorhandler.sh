#!/usr/bin/env bash
#
# errorhandler.sh — единый EXIT-хендлер и cleanup-хуки / unified EXIT handler and cleanup
# hooks
#
# @depends core/const, core/logger
#
# Идея / Idea:
# - любой модуль/скрипт может добавить очистку / any module/script can add cleanup:
#     cleanup::add my_cleanup_function
# - при завершении скрипта (даже при ошибке) cleanup выполнится / on script exit (even on
# error) cleanup will execute
#

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Core prerequisites
# Load core prerequisites if not already available
if ! declare -f bs::guard >/dev/null 2>&1; then
    source "$(dirname -- "${BASH_SOURCE[0]}")/prereq.sh"
fi
bs::guard "ERRORHANDLER" || return 0

# Зависимости / Dependencies
bs::source_relative "const.sh" "logger.sh"

declare -ga BS_CLEANUP_STACK=()

# @description Add cleanup function to stack / Добавить функцию очистки в стек
# @param $1 Function name to add to cleanup / Имя функции для добавления в очистку
# @example
#   cleanup::add my_cleanup_function
cleanup::add() {
	local fn="${1-}"
	if [[ -z "${fn}" ]]; then
		log::warn "cleanup::add: не указана функция"
		return "${E_INVALID:-2}"
	fi
	BS_CLEANUP_STACK+=("${fn}")
}

# @description Run all cleanup functions / Выполнить все функции очистки
# @example
#   cleanup::__run_all
cleanup::__run_all() {
	local i
	for ((i = ${#BS_CLEANUP_STACK[@]} - 1; i >= 0; i--)); do
		"${BS_CLEANUP_STACK[$i]}" || true
	done
	# Очищаем стек после прогона: повторный вызов (ручной + trap EXIT) безопасен
	# Clear stack after run: repeated call (manual + EXIT trap) is safe
	BS_CLEANUP_STACK=()
}

BS::__on_exit() {
	cleanup::__run_all
}

# @description Install EXIT trap running the cleanup stack (entry points only)
# / Установить EXIT-trap, выполняющий стек очистки (только для точек входа)
# @example
#   errorhandler::setup_trap
errorhandler::setup_trap() {
	trap 'BS::__on_exit' EXIT
}

# @description Log an error and return its code without exiting
# / Записать ошибку в лог и вернуть её код, не завершая скрипт
# @param $1 Function name where the error occurred / Имя функции, где произошла ошибка
# @param $2 Error message / Сообщение об ошибке
# @param $3 [optional] Error code (default: E_ERROR) / Код ошибки (по умолчанию E_ERROR)
# @return Error code / Код ошибки
# @example
#   errorhandler::throw "my::func" "Something failed" "${LIB_ERROR_FILE_NOT_FOUND}"
errorhandler::throw() {
	local -r func_name="${1:-unknown}"
	local -r message="${2:-}"
	local -r code="${3:-${E_ERROR:-1}}"

	# Логируем через log::error, если logger загружен, иначе — в stderr
	# Log via log::error if logger is loaded, otherwise to stderr
	if declare -F log::error >/dev/null 2>&1; then
		log::error "[${func_name}] ${message}"
	else
		printf 'ERROR [%s] %s\n' "${func_name}" "${message}" >&2
	fi

	return "${code}"
}

# @description Exit BS application with cleanup / Выход из приложения BS с очисткой
# @param $1 [optional] Exit code (default: 0) / Код выхода (по умолчанию 0)
# @example
#   BS::exit
#   BS::exit 1
bs::exit() {
    local -r exit_code="${1:-0}"
    # Run all cleanup functions / Запустить все функции очистки
    cleanup::__run_all
    exit "${exit_code}"
}

# @description Exit with error message and cleanup / Выход с сообщением об ошибке и
# очисткой
# @param $1 Error message / Сообщение об ошибке
# @param $2 Exit code (default: 1) / Код выхода (по умолчанию 1)
# @example
#   error::exit "Something went wrong" 2
error::exit() {
    local -r message="${1}"
    local -r exit_code="${2:-${E_ERROR:-1}}"
    
    log::error "${message}"
    bs::exit "${exit_code}"
}

# @description Exit with error message and backtrace / Выход с сообщением об ошибке и
# трассировкой
# @param $1 Error message / Сообщение об ошибке
# @param $2 Exit code (default: 1) / Код выхода (по умолчанию 1)
# @example
#   error::exit_with_backtrace "Critical error occurred" 3
error::exit_with_backtrace() {
    local -r message="${1}"
    local -r exit_code="${2:-${E_ERROR:-1}}"
    
    log::error "${message}"
    log::error "Backtrace:"
    
    # Print backtrace excluding this function
    local frame
    local bash_source_length=${#BASH_SOURCE[@]}
    for ((frame=1; frame<${bash_source_length}-1; frame++)); do
        log::error "  ${BASH_SOURCE[$frame+1]}:${BASH_LINENO[$frame]} ${FUNCNAME[$frame+1]}(...)"
    done
    
    bs::exit "${exit_code}"
}

# @description Handle error with custom handler / Обработка ошибки с пользовательским
# обработчиком
# @param $1 Error code / Код ошибки
# @param $2 Error message / Сообщение об ошибке
# @example
#   error::handle 127 "Command not found"
error::handle() {
    local -r error_code="${1}"
    local -r message="${2}"
    
    log::error "Error ${error_code}: ${message}"
    
    # Execute custom error handler if defined
    if function_exists "error::handler::${error_code}"; then
        "error::handler::${error_code}" "${message}"
    else
        # Default error handling
        error::exit "${message}" "${error_code}"
    fi
}

# @description Check if function exists / Проверить, существует ли функция
# @param $1 Function name / Имя функции
# @return 0 if function exists, 1 otherwise / 0 если функция существует, 1 в противном
# случае
function_exists() {
    local -r fn="${1}"
    declare -F "${fn}" >/dev/null 2>&1
}

# @description Set custom error handler for specific error code / Установить
# пользовательский обработчик для конкретного кода ошибки
# @param $1 Error code / Код ошибки
# @param $2 Handler function name / Имя функции-обработчика
# @example
#   error::set_handler 127 my_not_found_handler
error::set_handler() {
    local -r error_code="${1}"
    local -r handler="${2}"
    
    if function_exists "${handler}"; then
        # Create a named handler function
        eval "error::handler::${error_code}() { ${handler} \"\$@\"; }"
        log::debug "Set custom handler for error ${error_code}: ${handler}"
    else
        log::warn "Handler function does not exist: ${handler}"
        return 1
    fi
}

# @description Reset error handler for specific error code / Сбросить обработчик для
# конкретного кода ошибки
# @param $1 Error code / Код ошибки
# @example
#   error::reset_handler 127
error::reset_handler() {
    local -r error_code="${1}"
    
    unset -f "error::handler::${error_code}" 2>/dev/null
    log::debug "Reset handler for error ${error_code}"
}

# @description Try-catch-like error handling / Обработка ошибок в стиле try-catch
# @param $@ Command to execute / Команда для выполнения
# @example
#   error::try command_that_might_fail
error::try() {
    local -i result=0
    "$@" || result=$?

    if [[ ${result} -ne 0 ]]; then
        log::error "Command failed: $*"
        return "${result}"
    fi

    return 0
}

# @description Execute command with error handling and fallback / Выполнить команду с
# обработкой ошибок и запасным вариантом
# @param $1 Command to try / Команда для попытки
# @param $2 Fallback command / Запасная команда
# @example
#   error::try_with_fallback "critical_command" "fallback_command"
error::try_with_fallback() {
    local primary_cmd="${1}"
    local fallback_cmd="${2}"
    
    if ! error::try eval "${primary_cmd}"; then
        log::warn "Primary command failed, trying fallback: ${fallback_cmd}"
        eval "${fallback_cmd}"
    fi
}

# @description Execute command with retry logic / Выполнить команду с логикой повтора
# @param $1 Max retries / Максимум повторов
# @param $@ Command to execute / Команда для выполнения
# @example
#   error::retry 3 command_that_might_fail
error::retry() {
    local -r max_retries="${1}"
    shift
    local cmd=("$@")
    local -i attempt=1
    local -i result=0
    
    while [[ ${attempt} -le ${max_retries} ]]; do
        log::debug "Attempt ${attempt}/${max_retries}: ${cmd[*]}"
        "${cmd[@]}" && return 0
        result=$?
        
        if [[ ${attempt} -lt ${max_retries} ]]; then
            log::debug "Command failed, retrying in 1 second..."
            sleep 1
        fi
        
        ((attempt++))
    done
    
    log::error "Command failed after ${max_retries} attempts: ${cmd[*]}"
    return ${result}
}

# @description Ignore specific errors / Игнорировать конкретные ошибки
# @param $@ Commands to execute with error ignored / Команды для выполнения с
# игнорированием ошибок
# @example
#   error::ignore command_that_might_fail
error::ignore() {
    "$@" 2>/dev/null || true
}

# @description Error handling with timeout / Обработка ошибок с таймаутом
# @param $1 Timeout in seconds / Таймаут в секундах
# @param $@ Command to execute / Команда для выполнения
# @example
#   error::with_timeout 10 long_running_command
error::with_timeout() {
    local timeout="${1}"
    shift
    local cmd=("$@")
    
    if command -v timeout >/dev/null 2>&1; then
        timeout "${timeout}" "${cmd[@]}"
    else
        log::warn "timeout command not available, running without timeout: ${cmd[*]}"
        "${cmd[@]}"
    fi
}

# @description Panic handler for critical errors / Обработчик паники для критических
# ошибок
# @param $1 Critical error message / Сообщение о критической ошибке
# @example
#   error::panic "Critical system failure"
error::panic() {
    local -r message="${1}"

    log::error "PANIC: ${message}"
    log::error "System is in an inconsistent state. Terminating immediately."

    # Run cleanup functions
    cleanup::__run_all

    # Exit immediately with error code
    exit "${E_ERROR:-1}"
}

# @description Log error without exiting / Записать ошибку без выхода
# @param $1 Error message / Сообщение об ошибке
# @example
#   error::log "Non-fatal error occurred"
error::log() {
    local -r message="${1}"
    log::error "${message}"
}

# @description Handle error conditionally / Условная обработка ошибки
# @param $1 Condition command / Команда условия
# @param $2 Error message / Сообщение об ошибке
# @param $3 Exit code (default: 1) / Код выхода (по умолчанию 1)
# @example
#   error::conditional "command -v nonexistent >/dev/null 2>&1" "Command not found" 127
error::conditional() {
    local -r condition="${1}"
    local -r message="${2}"
    local -r exit_code="${3:-${E_ERROR:-1}}"
    
    if eval "${condition}"; then
        error::exit "${message}" "${exit_code}"
    fi
}

# @description Handle warning conditionally / Условная обработка предупреждения
# @param $1 Condition command / Команда условия
# @param $2 Warning message / Сообщение предупреждения
# @example
#   error::conditional_warning "check_deprecated_feature" "Feature is deprecated"
error::conditional_warning() {
    local -r condition="${1}"
    local -r message="${2}"
    
    if eval "${condition}"; then
        log::warn "${message}"
    fi
}

# @description Error handler for missing commands / Обработчик ошибок для отсутствующих
# команд
# @param $1 Command that was not found / Команда, которая не была найдена
# @example
#   error::handler::command_not_found "mycommand"
error::handler::command_not_found() {
    local -r cmd="${1}"
    log::error "Command not found: ${cmd}"

    # Check if the command exists in any package
    if command -v apt >/dev/null 2>&1; then
        local package
        package=$(apt-cache search "${cmd}" | head -n 1 | awk '{print $1}')
        if [[ -n "${package}" ]]; then
            log::info "You might need to install package: ${package}"
        fi
    elif command -v dnf >/dev/null 2>&1; then
        local package
        package=$(dnf search "${cmd}" 2>/dev/null | grep -E '^\w' | head -n 1 | awk '{print $1}')
        if [[ -n "${package}" ]]; then
            log::info "You might need to install package: ${package}"
        fi
    fi

    error::exit "Command '${cmd}' not found" 127
}