#!/usr/bin/env bs
# shellcheck shell=bash
# time.sh — Date and time configuration for system setup / Конфигурация даты и времени для
# настройки системы
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
# Load core prerequisites if not already available
if ! declare -f bs::guard >/dev/null 2>&1; then
    source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/prereq.sh"
fi
bs::guard "SYSTEM_TIME" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @description Set system timezone / Установить системный часовой пояс
# @param $1 Timezone (e.g., "Europe/Moscow", "America/New_York") / Часовой пояс (например,
# "Europe/Moscow", "America/New_York")
# @example
#   system::time::timezone "Europe/Moscow"
system::time::timezone() {
    local timezone="${1:-UTC}"
    
    # Validate timezone / Проверить валидность часового пояса
    if [[ ! -f "/usr/share/zoneinfo/${timezone}" ]]; then
        log::warn "Invalid timezone: ${timezone}"
        return 1
    fi
    
    # For systemd-based systems / Для систем на базе systemd
    if utils::has timedatectl; then
        utils::ignore timedatectl set-timezone "${timezone}"
    else
        # Fallback for non-systemd systems / Резервный вариант для систем без systemd
        if [[ -f "/etc/localtime" ]]; then
            ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime
        fi
        
        # Set timezone in configuration file / Установить часовой пояс в файле
        # конфигурации
        if [[ -f "/etc/timezone" ]]; then
            echo "${timezone}" > /etc/timezone
        fi
    fi
    
    log::info "System timezone set to ${timezone}"
}

# @description Enable or disable NTP synchronization / Включить или отключить
# синхронизацию NTP
# @param $1 "true" to enable, "false" to disable / "true" для включения, "false" для
# отключения
# @example
#   system::time::ntp "true"
system::time::ntp() {
    local enable="${1:-true}"
    
    if utils::has timedatectl; then
        if [[ "${enable}" == "true" ]]; then
            utils::ignore timedatectl set-ntp true
            log::info "NTP synchronization enabled"
        else
            utils::ignore timedatectl set-ntp false
            log::info "NTP synchronization disabled"
        fi
    else
        # Fallback for systems with ntpdate or chrony / Резервный вариант для систем с
        # ntpdate или chrony
        if [[ "${enable}" == "true" ]]; then
            if utils::has ntpd; then
                utils::ignore systemctl enable ntpd
                utils::ignore systemctl start ntpd
            elif utils::has chronyd; then
                utils::ignore systemctl enable chronyd
                utils::ignore systemctl start chronyd
            fi
            log::info "NTP service enabled"
        else
            if utils::has ntpd; then
                utils::ignore systemctl stop ntpd
                utils::ignore systemctl disable ntpd
            elif utils::has chronyd; then
                utils::ignore systemctl stop chronyd
                utils::ignore systemctl disable chronyd
            fi
            log::info "NTP service disabled"
        fi
    fi
}

# @description Set system date and time (manual) / Установить системную дату и время
# (вручную)
# @param $1 Date and time in format "YYYY-MM-DD HH:MM:SS" / Дата и время в формате
# "YYYY-MM-DD HH:MM:SS"
# @example
#   system::time::set "2026-01-04 12:00:00"
system::time::set() {
    local datetime="${1}"
    
    if [[ -z "${datetime}" ]]; then
        log::warn "Date and time not specified"
        return 1
    fi
    
    # For systemd-based systems / Для систем на базе systemd
    if utils::has timedatectl; then
        utils::ignore timedatectl set-time "${datetime}"
    else
        # Fallback for non-systemd systems / Резервный вариант для систем без systemd
        if utils::has date; then
            # Format depends on system, trying common formats / Формат зависит от системы,
            # пробуем распространенные форматы
            utils::ignore date -s "${datetime}"
        fi
    fi
    
    log::info "System date and time set to ${datetime}"
}

# @description List available timezones / Показать доступные часовые пояса
# @example
#   system::time::list_timezones
system::time::list_timezones() {
    if utils::has timedatectl; then
        utils::ignore timedatectl list-timezones
    else
        # Fallback for non-systemd systems / Резервный вариант для систем без systemd
        if [[ -d "/usr/share/zoneinfo" ]]; then
            find /usr/share/zoneinfo -type f -not -path "*/.*" -not -path "*/posix/*" -not -path "*/right/*" | \
                sed 's|/usr/share/zoneinfo/||' | sort
        fi
    fi
}
