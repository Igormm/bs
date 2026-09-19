#!/usr/bin/env bs
# shellcheck shell=bash
# services.sh — Service management for system setup / Управление сервисами для настройки
# системы
# @depends core/const, core/logger, core/utils, lib/system/distro

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_SERVICES" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "distro.sh"

# @description Start a system service / Запустить системный сервис
# @param $1 Service name / Имя сервиса
# @example
#   system::services::start "sshd"
system::services::start() {
    local service="${1}"
    
    if is::empty "${service}"; then
        log::warn "Service name not specified"
        return "${E_ERROR}"
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if utils::has systemctl; then
        utils::ignore systemctl start "${service}"
        log::info "Service ${service} started (systemd)"
    else
        # Fallback to service command / Резервный вариант команды service
        if utils::has service; then
            utils::ignore service "${service}" start
            log::info "Service ${service} started (service)"
        else
            # Fallback to direct init script / Резервный вариант прямого init скрипта
            if is::executable "/etc/init.d/${service}"; then
                utils::ignore "/etc/init.d/${service}" start
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
    local service="${1}"
    
    if is::empty "${service}"; then
        log::warn "Service name not specified"
        return "${E_ERROR}"
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if utils::has systemctl; then
        utils::ignore systemctl stop "${service}"
        log::info "Service ${service} stopped (systemd)"
    else
        # Fallback to service command / Резервный вариант команды service
        if utils::has service; then
            utils::ignore service "${service}" stop
            log::info "Service ${service} stopped (service)"
        else
            # Fallback to direct init script / Резервный вариант прямого init скрипта
            if is::executable "/etc/init.d/${service}"; then
                utils::ignore "/etc/init.d/${service}" stop
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
    local service="${1}"
    
    if is::empty "${service}"; then
        log::warn "Service name not specified"
        return "${E_ERROR}"
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if utils::has systemctl; then
        utils::ignore systemctl enable "${service}"
        log::info "Service ${service} enabled (systemd)"
    else
        # Fallback to update-rc.d or chkconfig / Резервный вариант update-rc.d или
        # chkconfig
        if utils::has update-rc.d; then
            utils::ignore update-rc.d "${service}" defaults
            log::info "Service ${service} enabled (update-rc.d)"
        elif utils::has chkconfig; then
            utils::ignore chkconfig "${service}" on
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
    local service="${1}"
    
    if is::empty "${service}"; then
        log::warn "Service name not specified"
        return "${E_ERROR}"
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if utils::has systemctl; then
        utils::ignore systemctl disable "${service}"
        log::info "Service ${service} disabled (systemd)"
    else
        # Fallback to update-rc.d or chkconfig / Резервный вариант update-rc.d или
        # chkconfig
        if utils::has update-rc.d; then
            utils::ignore update-rc.d -f "${service}" remove
            log::info "Service ${service} disabled (update-rc.d)"
        elif utils::has chkconfig; then
            utils::ignore chkconfig "${service}" off
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
    local service="${1}"
    
    if is::empty "${service}"; then
        log::warn "Service name not specified"
        return "${E_ERROR}"
    fi
    
    # Try systemd first / Попробовать systemd сначала
    if utils::has systemctl; then
        utils::ignore systemctl restart "${service}"
        log::info "Service ${service} restarted (systemd)"
    else
        # Fallback to service command / Резервный вариант команды service
        if utils::has service; then
            utils::ignore service "${service}" restart
            log::info "Service ${service} restarted (service)"
        else
            # Fallback to direct init script / Резервный вариант прямого init скрипта
            if is::executable "/etc/init.d/${service}"; then
                utils::ignore "/etc/init.d/${service}" restart
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
    local service="${1}"
    
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
            utils::ignore service "${service}" status
        else
            # Fallback to direct init script / Резервный вариант прямого init скрипта
            if is::executable "/etc/init.d/${service}"; then
                utils::ignore "/etc/init.d/${service}" status
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
