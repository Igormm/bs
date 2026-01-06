#!/usr/bin/env bs
# time.sh — Date and time configuration for system setup / Конфигурация даты и времени для
# настройки системы

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
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-timezone "${timezone}" 2>/dev/null || true
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
    
    if command -v timedatectl >/dev/null 2>&1; then
        if [[ "${enable}" == "true" ]]; then
            timedatectl set-ntp true 2>/dev/null || true
            log::info "NTP synchronization enabled"
        else
            timedatectl set-ntp false 2>/dev/null || true
            log::info "NTP synchronization disabled"
        fi
    else
        # Fallback for systems with ntpdate or chrony / Резервный вариант для систем с
        # ntpdate или chrony
        if [[ "${enable}" == "true" ]]; then
            if command -v ntpd >/dev/null 2>&1; then
                systemctl enable ntpd 2>/dev/null || true
                systemctl start ntpd 2>/dev/null || true
            elif command -v chronyd >/dev/null 2>&1; then
                systemctl enable chronyd 2>/dev/null || true
                systemctl start chronyd 2>/dev/null || true
            fi
            log::info "NTP service enabled"
        else
            if command -v ntpd >/dev/null 2>&1; then
                systemctl stop ntpd 2>/dev/null || true
                systemctl disable ntpd 2>/dev/null || true
            elif command -v chronyd >/dev/null 2>&1; then
                systemctl stop chronyd 2>/dev/null || true
                systemctl disable chronyd 2>/dev/null || true
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
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-time "${datetime}" 2>/dev/null || true
    else
        # Fallback for non-systemd systems / Резервный вариант для систем без systemd
        if command -v date >/dev/null 2>&1; then
            # Format depends on system, trying common formats / Формат зависит от системы,
            # пробуем распространенные форматы
            date -s "${datetime}" 2>/dev/null || true
        fi
    fi
    
    log::info "System date and time set to ${datetime}"
}

# @description List available timezones / Показать доступные часовые пояса
# @example
#   system::time::list_timezones
system::time::list_timezones() {
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl list-timezones 2>/dev/null || true
    else
        # Fallback for non-systemd systems / Резервный вариант для систем без systemd
        if [[ -d "/usr/share/zoneinfo" ]]; then
            find /usr/share/zoneinfo -type f -not -path "*/.*" -not -path "*/posix/*" -not -path "*/right/*" | \
                sed 's|/usr/share/zoneinfo/||' | sort
        fi
    fi
}