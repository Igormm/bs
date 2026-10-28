#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], local/declare flags, regex =~ / needs bash constructs: double-bracket [[ ]], local/declare flags, regex =~
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

# @description Set the list of NTP servers/pools / Задать список NTP-серверов/пулов
# @param $@ servers (hostnames or IPs) / серверы (имена или IP)
# @example
#   system::time::ntp_servers "pool.ntp.org" "ru.pool.ntp.org"
system::time::ntp_servers() {
    if [ $# -eq 0 ]; then
        log::warn "At least one NTP server required"
        return "${E_INVALID}"
    fi

    local server joined=""
    for server in "$@"; do
        # hostname / IPv4 / IPv6, no shell metacharacters / имя или IP, без метасимволов
        if [[ ! "${server}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
            log::warn "Invalid NTP server: ${server}"
            return "${E_INVALID}"
        fi
        joined="${joined}${joined:+ }${server}"
    done

    local file=""
    if [[ -n "${BS_NTP_CONF:-}" ]]; then
        file="${BS_NTP_CONF}"
    elif is::file /etc/chrony.conf; then
        file=/etc/chrony.conf
    elif is::file /etc/ntp.conf; then
        file=/etc/ntp.conf
    elif is::file /etc/systemd/timesyncd.conf; then
        file=/etc/systemd/timesyncd.conf
    else
        log::error "No NTP configuration found (chrony.conf / ntp.conf / timesyncd.conf)"
        return "${E_ERROR}"
    fi

    local -r tmp="${file}.tmp.$$"
    if grep -q '^\[Time\]' "${file}"; then
        # systemd-timesyncd: NTP= line in the [Time] section / systemd-timesyncd: строка NTP= в секции [Time]
        if grep -q '^NTP=' "${file}"; then
            # серверы проверены: только [A-Za-z0-9._:-], безопасно для sed / servers are
            # validated to [A-Za-z0-9._:-], safe for the sed replacement
            sed -i "s/^NTP=.*/NTP=${joined}/" "${file}" || { log::error "Cannot edit ${file}"; return "${E_ERROR}"; }
        elif grep -q '^\[Time\]' "${file}"; then
            awk -v ntp="NTP=${joined}" '/^\[Time\]/ { print; print ntp; next } { print }' \
                "${file}" > "${tmp}" || { rm -f "${tmp}"; log::error "Cannot edit ${file}"; return "${E_ERROR}"; }
            mv -f -- "${tmp}" "${file}" || { rm -f "${tmp}"; log::error "Cannot write ${file}"; return "${E_ERROR}"; }
        else
            printf 'NTP=%s\n' "${joined}" >> "${file}" || { log::error "Cannot write ${file}"; return "${E_ERROR}"; }
        fi
    else
        # chrony / ntpd: replace server/pool lines, keep the rest / chrony / ntpd: заменить строки server/pool
        grep -vE '^[[:space:]]*(server|pool)[[:space:]]' "${file}" > "${tmp}" || true
        for server in "$@"; do
            printf 'server %s\n' "${server}" >> "${tmp}"
        done
        mv -f -- "${tmp}" "${file}" || { rm -f "${tmp}"; log::error "Cannot write ${file}"; return "${E_ERROR}"; }
    fi

    log::info "NTP servers set: ${joined}"
    return 0
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
