#!/usr/bin/env bs
# shellcheck shell=bash
# safety.sh — Safety features for newbies / Функции безопасности для новичков
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "SYSTEM_SAFETY" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# Safety levels / Уровни безопасности
declare -g SAFETY_LEVEL="normal"  # paranoid, strict, normal, relaxed
declare -g SAFETY_DRY_RUN="false" # true/false

# @description Set safety level / Установить уровень безопасности
# @param $1 Safety level (paranoid|strict|normal|relaxed) / Уровень безопасности
# @example
#   safety::set_level "strict"
safety::set_level() {
    local level="${1:-normal}"

    case "${level}" in
        paranoid|strict|normal|relaxed)
            SAFETY_LEVEL="${level}"
            log::info "Safety level set to: ${level}"
            return 0
            ;;
        *)
            log::error "Invalid safety level: ${level}. Use: paranoid, strict, normal, relaxed"
            return 1
            ;;
    esac
}

# @description Enable or disable dry-run mode / Включить или отключить режим dry-run
# @param $1 Enable dry-run (true|false) / Включить dry-run
# @example
#   safety::dry_run "true"
safety::dry_run() {
    local enable="${1:-false}"

    case "${enable}" in
        true|false)
            SAFETY_DRY_RUN="${enable}"
            log::info "Dry-run mode: ${enable}"
            return 0
            ;;
        *)
            log::error "Invalid dry-run value: ${enable}. Use: true, false"
            return 1
            ;;
    esac
}

# @description Check if operation needs confirmation / Проверить, нужна ли операция
# подтверждения
# @param $1 Risk level (low|medium|high|critical) / Уровень риска
# @return 0 if confirmation needed, 1 if not / 0 если нужно подтверждение, 1 если нет
safety::needs_confirmation() {
    local risk="${1:-medium}"

    # Dry-run always needs confirmation to show what would happen / Dry-run всегда требует
    # подтверждения чтобы показать что произойдет
    if [[ "${SAFETY_DRY_RUN}" == "true" ]]; then
        return 0
    fi

    case "${SAFETY_LEVEL}" in
        paranoid)
            # Everything needs confirmation / Все требует подтверждения
            return 0
            ;;
        strict)
            # High and critical operations need confirmation / Высокий и критический
            # уровень требуют подтверждения
            [[ "${risk}" == "high" || "${risk}" == "critical" ]]
            return $?
            ;;
        normal)
            # Only critical operations need confirmation / Только критические операции
            # требуют подтверждения
            [[ "${risk}" == "critical" ]]
            return $?
            ;;
        relaxed)
            # Nothing needs confirmation / Ничего не требует подтверждения
            return 1
            ;;
    esac
}

# @description Ask for user confirmation / Запросить подтверждение пользователя
# @param $1 Operation description / Описание операции
# @return 0 if confirmed, 1 if not / 0 если подтверждено, 1 если нет
safety::confirm() {
    local description="${1}"

    if [[ "${SAFETY_DRY_RUN}" == "true" ]]; then
        log::info "[DRY-RUN] Would execute: ${description}"
        return 0
    fi

    local ans
    read -r -p "${description}. Continue? [y/N]: " ans
    [[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

# @description Execute operation with safety checks / Выполнить операцию с проверками
# безопасности
# @param $1 Risk level / Уровень риска
# @param $2 Description / Описание
# @param $@ Command to execute / Команда для выполнения
# @return exit code of command / код выхода команды
safety::execute() {
    local risk="${1}"
    local description="${2}"
    shift 2

    if safety::needs_confirmation "${risk}"; then
        if ! safety::confirm "${description}"; then
            log::info "Operation cancelled by user"
            return 1
        fi
    fi

    if [[ "${SAFETY_DRY_RUN}" == "true" ]]; then
        log::info "[DRY-RUN] Would execute: $*"
        return 0
    fi

    "$@"
}

# @description Validate file path for safety / Проверить путь к файлу на безопасность
# @param $1 Path to validate / Путь для проверки
# @return 0 if safe, 1 if not / 0 если безопасно, 1 если нет
safety::validate_path() {
    local path="${1}"

    # Check for dangerous paths / Проверить на опасные пути
    local dangerous_paths=(
        "/"
        "/bin"
        "/sbin"
        "/usr"
        "/etc"
        "/var"
        "/root"
        "/boot"
        "/sys"
        "/proc"
        "/dev"
    )

    for dangerous in "${dangerous_paths[@]}"; do
        if [[ "${path}" == "${dangerous}" ]]; then
            log::error "Dangerous path: ${path} (system directory)"
            return 1
        fi
    done

    # Check if path exists and is writable / Проверить существует ли путь и доступен ли
    # для записи
    if [[ -e "${path}" && ! -w "${path}" ]]; then
        log::error "Path not writable: ${path}"
        return 1
    fi

    return 0
}

# @description Show current safety settings / Показать текущие настройки безопасности
# @example
#   safety::status
safety::status() {
    echo "=== Safety Settings ==="
    echo "Level: ${SAFETY_LEVEL}"
    echo "Dry-run: ${SAFETY_DRY_RUN}"
    echo ""
    echo "Risk levels that require confirmation:"
    case "${SAFETY_LEVEL}" in
        paranoid) echo "  - All operations" ;;
        strict)   echo "  - High and critical operations" ;;
        normal)   echo "  - Critical operations only" ;;
        relaxed)  echo "  - No operations" ;;
    esac
}
