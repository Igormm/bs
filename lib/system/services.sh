#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4 — нужны конструкции bash: bash-only syntax / needs bash constructs: bash-only syntax
# services.sh — Service management for system setup / Управление сервисами для настройки
# системы
# @depends core/const, core/logger, core/utils, lib/system/distro

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_SERVICES" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "distro.sh"

# @private Run a service command; on failure log its output and return E_ERROR
# @private Выполнить команду сервиса; при неудаче записать её вывод и вернуть E_ERROR
# @param $@ Command and arguments / Команда и аргументы
system::services::__exec() {
    local out
    if out="$("$@" 2>&1)"; then
        return 0
    fi
    log::error "Command failed / Команда не удалась: $* ${out:+(${out})}"
    return "${E_ERROR}"
}

# @private Status via a legacy command: its exit code is the answer
# @private Статус через старую команду: ответ — её код возврата
# @param $@ Command and arguments / Команда и аргументы
system::services::__status_cmd() {
    if utils::quiet "$@"; then
        log::info "Service is running / Сервис работает: $*"
        return 0
    fi
    log::info "Service is not running / Сервис не работает: $*"
    return 1
}

# @description Start a system service / Запустить системный сервис
# @param $1 Service name / Имя сервиса
# @example
#   system::services::start "sshd"
system::services::start() {
    local service="${1:-}"
    
    if is::empty "${service}"; then
        log::warn "Service name not specified"
        return "${E_ERROR}"
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if utils::has systemctl; then
        system::services::__exec systemctl start "${service}" || return "${E_ERROR}"
        log::info "Service ${service} started (systemd)"
    else
        # Fallback to service command / Резервный вариант команды service
        if utils::has service; then
            system::services::__exec service "${service}" start || return "${E_ERROR}"
            log::info "Service ${service} started (service)"
        else
            # Fallback to direct init script / Резервный вариант прямого init скрипта
            if is::executable "/etc/init.d/${service}"; then
                system::services::__exec "/etc/init.d/${service}" start || return "${E_ERROR}"
                log::info "Service ${service} started (init.d)"
            else
                log::warn "No suitable method to start service ${service}"
                return "${E_ERROR}"
            fi
        fi
    fi
}

# @description Stop a system service / Остановить системный сервис
# @param $1 Service name / Имя сервиса
# @example
#   system::services::stop "sshd"
system::services::stop() {
    local service="${1:-}"
    
    if is::empty "${service}"; then
        log::warn "Service name not specified"
        return "${E_ERROR}"
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if utils::has systemctl; then
        system::services::__exec systemctl stop "${service}" || return "${E_ERROR}"
        log::info "Service ${service} stopped (systemd)"
    else
        # Fallback to service command / Резервный вариант команды service
        if utils::has service; then
            system::services::__exec service "${service}" stop || return "${E_ERROR}"
            log::info "Service ${service} stopped (service)"
        else
            # Fallback to direct init script / Резервный вариант прямого init скрипта
            if is::executable "/etc/init.d/${service}"; then
                system::services::__exec "/etc/init.d/${service}" stop || return "${E_ERROR}"
                log::info "Service ${service} stopped (init.d)"
            else
                log::warn "No suitable method to stop service ${service}"
                return "${E_ERROR}"
            fi
        fi
    fi
}

# @description Enable a system service to start at boot / Включить автозапуск системного
# сервиса при загрузке
# @param $1 Service name / Имя сервиса
# @example
#   system::services::enable "sshd"
system::services::enable() {
    local service="${1:-}"
    
    if is::empty "${service}"; then
        log::warn "Service name not specified"
        return "${E_ERROR}"
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if utils::has systemctl; then
        system::services::__exec systemctl enable "${service}" || return "${E_ERROR}"
        log::info "Service ${service} enabled (systemd)"
    else
        # Fallback to update-rc.d or chkconfig / Резервный вариант update-rc.d или
        # chkconfig
        if utils::has update-rc.d; then
            system::services::__exec update-rc.d "${service}" defaults || return "${E_ERROR}"
            log::info "Service ${service} enabled (update-rc.d)"
        elif utils::has chkconfig; then
            system::services::__exec chkconfig "${service}" on || return "${E_ERROR}"
            log::info "Service ${service} enabled (chkconfig)"
        else
            log::warn "No suitable method to enable service ${service}"
            return "${E_ERROR}"
        fi
    fi
}

# @description Disable a system service from starting at boot / Отключить автозапуск
# системного сервиса при загрузке
# @param $1 Service name / Имя сервиса
# @example
#   system::services::disable "sshd"
system::services::disable() {
    local service="${1:-}"
    
    if is::empty "${service}"; then
        log::warn "Service name not specified"
        return "${E_ERROR}"
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if utils::has systemctl; then
        system::services::__exec systemctl disable "${service}" || return "${E_ERROR}"
        log::info "Service ${service} disabled (systemd)"
    else
        # Fallback to update-rc.d or chkconfig / Резервный вариант update-rc.d или
        # chkconfig
        if utils::has update-rc.d; then
            system::services::__exec update-rc.d -f "${service}" remove || return "${E_ERROR}"
            log::info "Service ${service} disabled (update-rc.d)"
        elif utils::has chkconfig; then
            system::services::__exec chkconfig "${service}" off || return "${E_ERROR}"
            log::info "Service ${service} disabled (chkconfig)"
        else
            log::warn "No suitable method to disable service ${service}"
            return "${E_ERROR}"
        fi
    fi
}

# @description Restart a system service / Перезапустить системный сервис
# @param $1 Service name / Имя сервиса
# @example
#   system::services::restart "sshd"
system::services::restart() {
    local service="${1:-}"
    
    if is::empty "${service}"; then
        log::warn "Service name not specified"
        return "${E_ERROR}"
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if utils::has systemctl; then
        system::services::__exec systemctl restart "${service}" || return "${E_ERROR}"
        log::info "Service ${service} restarted (systemd)"
    else
        # Fallback to service command / Резервный вариант команды service
        if utils::has service; then
            system::services::__exec service "${service}" restart || return "${E_ERROR}"
            log::info "Service ${service} restarted (service)"
        else
            # Fallback to direct init script / Резервный вариант прямого init скрипта
            if is::executable "/etc/init.d/${service}"; then
                system::services::__exec "/etc/init.d/${service}" restart || return "${E_ERROR}"
                log::info "Service ${service} restarted (init.d)"
            else
                log::warn "No suitable method to restart service ${service}"
                return "${E_ERROR}"
            fi
        fi
    fi
}

# @description Check if a service is active/running / Проверить, активен ли сервис/запущен
# ли
# @param $1 Service name / Имя сервиса
# @example
#   system::services::status "sshd"
system::services::status() {
    local service="${1:-}"
    
    if is::empty "${service}"; then
        log::warn "Service name not specified"
        return "${E_ERROR}"
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if utils::has systemctl; then
        if utils::quiet_err systemctl is-active --quiet "${service}"; then
            log::info "Service ${service} is running"
            return 0
        else
            log::info "Service ${service} is not running"
            return 1
        fi
    else
        # Fallback to service command / Резервный вариант команды service
        if utils::has service; then
            system::services::__status_cmd service "${service}" status
        else
            # Fallback to direct init script / Резервный вариант прямого init скрипта
            if is::executable "/etc/init.d/${service}"; then
                system::services::__status_cmd "/etc/init.d/${service}" status
            else
                log::warn "No suitable method to check status of service ${service}"
                return "${E_ERROR}"
            fi
        fi
    fi
}

# @description List all system services / Показать все системные сервисы
# @example
#   system::services::list
system::services::list() {
    # Try systemd first / Попробовать systemd сначала
    if utils::has systemctl; then
        utils::quiet_err systemctl list-units --type=service --all | grep -E "^[a-zA-Z]" | awk '{print $1}'
    else
        # Fallback to listing init scripts / Резервный вариант списка init скриптов
        if is::dir "/etc/init.d"; then
            utils::quiet_err ls -1 /etc/init.d/ | grep -v "README"
        else
            log::warn "No suitable method to list services"
            return "${E_ERROR}"
        fi
    fi
}
