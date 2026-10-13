#!/usr/bin/env bs
# shellcheck shell=bash
# time.sh — Date and time configuration for system setup / Конфигурация даты и времени для
# настройки системы
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
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
    local -r zoneinfo="${BS_ZONEINFO_DIR:-/usr/share/zoneinfo}"
    
    # Validate timezone: a plain Region/City name, no "..", no absolute path
    # Проверить часовой пояс: обычное имя Region/City, без "..", без абсолютного пути
    if [[ ! "${timezone}" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] \
        || ! is::file "${zoneinfo}/${timezone}"; then
        log::warn "Invalid timezone: ${timezone}"
        return "${E_ERROR}"
    fi
    
    # For systemd-based systems / Для систем на базе systemd
    if utils::has timedatectl; then
        if ! utils::quiet timedatectl set-timezone "${timezone}"; then
            log::error "timedatectl failed to set timezone ${timezone}"
            return "${E_ERROR}"
        fi
    else
        # Fallback for non-systemd systems / Резервный вариант для систем без systemd
        if ! ln -sf "${zoneinfo}/${timezone}" "${BS_LOCALTIME:-/etc/localtime}"; then
            log::error "Cannot link ${BS_LOCALTIME:-/etc/localtime}"
            return "${E_ERROR}"
        fi
        
        # Set timezone in configuration file / Установить часовой пояс в файле
        # конфигурации
        if is::file "${BS_TIMEZONE_FILE:-/etc/timezone}"; then
            if ! printf '%s\n' "${timezone}" > "${BS_TIMEZONE_FILE:-/etc/timezone}"; then
                log::error "Cannot write ${BS_TIMEZONE_FILE:-/etc/timezone}"
                return "${E_ERROR}"
            fi
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
    
    # Only true/false: any other word used to switch NTP off silently
    # Только true/false: любое другое слово раньше молча выключало NTP
    if [[ "${enable}" != "true" && "${enable}" != "false" ]]; then
        log::warn "Invalid value: ${enable} (use true or false)"
        return "${E_INVALID}"
    fi
    
    # For systemd-based systems / Для систем на базе systemd
    if utils::has timedatectl; then
        if ! utils::quiet timedatectl set-ntp "${enable}"; then
            log::error "timedatectl set-ntp ${enable} failed"
            return "${E_ERROR}"
        fi
        if [[ "${enable}" == "true" ]]; then
            log::info "NTP synchronization enabled"
        else
            log::info "NTP synchronization disabled"
        fi
        return 0
    fi
    
    # Fallback: ntpd or chronyd / Резервный вариант: ntpd или chronyd
    local daemon=""
    if utils::has ntpd; then
        daemon="ntpd"
    elif utils::has chronyd; then
        daemon="chronyd"
    else
        log::warn "No NTP service (ntpd/chronyd) found"
        return "${E_ERROR}"
    fi
    if [[ "${enable}" == "true" ]]; then
        if ! utils::quiet systemctl enable "${daemon}" || ! utils::quiet systemctl start "${daemon}"; then
            log::error "Cannot enable ${daemon}"
            return "${E_ERROR}"
        fi
        log::info "NTP service enabled"
    else
        if ! utils::quiet systemctl stop "${daemon}" || ! utils::quiet systemctl disable "${daemon}"; then
            log::error "Cannot disable ${daemon}"
            return "${E_ERROR}"
        fi
        log::info "NTP service disabled"
    fi
}

# @description Set system date and time (manual) / Установить системную дату и время
# (вручную)
# @param $1 Date and time in format "YYYY-MM-DD HH:MM:SS" / Дата и время в формате
# "YYYY-MM-DD HH:MM:SS"
# @example
#   system::time::set "2026-01-04 12:00:00"
system::time::set() {
    local datetime="${1:-}"
    
    if is::empty "${datetime}"; then
        log::warn "Date and time not specified"
        return "${E_ERROR}"
    fi
    
    if utils::has timedatectl; then
        # Fails while NTP synchronization is on — that is a real failure, not success
        # Падает, пока включена NTP-синхронизация — это настоящий сбой, а не успех
        if ! utils::quiet timedatectl set-time "${datetime}"; then
            log::error "timedatectl set-time failed (is NTP on? try: system::time::ntp false)"
            return "${E_ERROR}"
        fi
    elif utils::has date; then
        if ! utils::quiet date -s "${datetime}"; then
            log::error "date -s failed for: ${datetime}"
            return "${E_ERROR}"
        fi
    else
        log::error "Neither timedatectl nor date available"
        return "${E_ERROR}"
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
        if is::dir "/usr/share/zoneinfo"; then
            find /usr/share/zoneinfo -type f -not -path "*/.*" -not -path "*/posix/*" -not -path "*/right/*" | \
                sed 's|/usr/share/zoneinfo/||' | sort
        fi
    fi
}
