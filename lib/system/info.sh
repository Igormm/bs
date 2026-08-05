#!/usr/bin/env bs
# shellcheck shell=bash
# info.sh — System information for system setup / Системная информация для настройки
# системы
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_INFO" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @description Get operating system information / Получить информацию об операционной
# системе
# @example
#   system::info::os
system::info::os() {
    echo "=== Operating System ==="
    
    # Try /etc/os-release first (modern standard) / Попробовать /etc/os-release сначала
    # (современный стандарт)
    if [[ -f /etc/os-release ]]; then
        # Read in a subshell to avoid polluting current environment
        # Читаем в подshell, чтобы не засорять текущее окружение
        (
            source /etc/os-release
            echo "Name: ${NAME:-Unknown}"
            echo "Version: ${VERSION:-Unknown}"
            echo "ID: ${ID:-Unknown}"
            echo "ID_LIKE: ${ID_LIKE:-Unknown}"
            echo "Version ID: ${VERSION_ID:-Unknown}"
            echo "Pretty Name: ${PRETTY_NAME:-Unknown}"
        )
    # Fallback to lsb_release / Резервный вариант lsb_release
    elif utils::has lsb_release; then
        utils::quiet_err lsb_release -a
    # Fallback to uname / Резервный вариант uname
    elif utils::has uname; then
        utils::quiet_err uname -a
    else
        log::warn "Cannot determine OS information"
        return 1
    fi
}

# @description Get kernel version / Получить версию ядра
# @example
#   system::info::kernel
system::info::kernel() {
    echo "=== Kernel Information ==="
    
    if utils::has uname; then
        echo "Kernel: $(uname -s)"
        echo "Release: $(uname -r)"
        echo "Version: $(uname -v)"
        echo "Machine: $(uname -m)"
        echo "Processor: $(uname -p)"
        echo "Hardware: $(uname -i)"
        echo "Full: $(uname -a)"
    else
        log::error "uname command not found"
        return 1
    fi
}

# @description Get system hostname / Получить имя хоста системы
# @example
#   system::info::hostname
system::info::hostname() {
    echo "=== Hostname Information ==="
    
    if utils::has hostname; then
        echo "Hostname: $(utils::quiet_err hostname)"
        echo "FQDN: $(utils::quiet_err hostname -f || hostname)"
        echo "Short: $(utils::quiet_err hostname -s || hostname)"
    # Try hostnamectl (systemd) / Попробовать hostnamectl (systemd)
    elif utils::has hostnamectl; then
        utils::quiet_err hostnamectl
    # Fallback to /etc/hostname / Резервный вариант /etc/hostname
    elif [[ -f /etc/hostname ]]; then
        echo "Hostname: $(utils::quiet_err cat /etc/hostname)"
    else
        log::warn "Cannot determine hostname"
        return 1
    fi
}

# @description Get system uptime / Получить время работы системы
# @example
#   system::info::uptime
system::info::uptime() {
    echo "=== System Uptime ==="
    
    if utils::has uptime; then
        utils::quiet_err uptime
    # Fallback to /proc/uptime / Резервный вариант /proc/uptime
    elif [[ -r /proc/uptime ]]; then
        local uptime_seconds
        uptime_seconds=$(utils::quiet_err cut -d' ' -f1 /proc/uptime | cut -d. -f1)
        if [[ -n "${uptime_seconds}" ]]; then
            local days=$((uptime_seconds / 86400))
            local hours=$(((uptime_seconds % 86400) / 3600))
            local minutes=$(((uptime_seconds % 3600) / 60))
            echo "Uptime: ${days} days, ${hours} hours, ${minutes} minutes"
        fi
    else
        log::warn "Cannot determine uptime"
        return 1
    fi
}

# @description Get CPU information / Получить информацию о процессоре
# @example
#   system::info::cpu
system::info::cpu() {
    echo "=== CPU Information ==="
    
    # Try /proc/cpuinfo / Попробовать /proc/cpuinfo
    if [[ -r /proc/cpuinfo ]]; then
        echo "Model: $(utils::quiet_err grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')"
        echo "Cores: $(utils::quiet_err grep -c "^processor" /proc/cpuinfo)"
        echo "Physical CPUs: $(utils::quiet_err grep "physical id" /proc/cpuinfo | sort -u | wc -l)"
        echo "CPU MHz: $(utils::quiet_err grep -m1 "cpu MHz" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')"
        echo "Cache: $(utils::quiet_err grep -m1 "cache size" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')"
    # Try lscpu (modern alternative) / Попробовать lscpu (современная альтернатива)
    elif utils::has lscpu; then
        utils::quiet_err lscpu
    else
        log::warn "Cannot determine CPU information"
        return 1
    fi
}

# @description Get memory information / Получить информацию о памяти
# @example
#   system::info::memory
system::info::memory() {
    echo "=== Memory Information ==="
    
    # Try free command first / Попробовать команду free сначала
    if utils::has free; then
        utils::quiet_err free -h
        echo ""
        echo "Detailed:"
        utils::quiet_err free -m
    # Fallback to /proc/meminfo / Резервный вариант /proc/meminfo
    elif [[ -r /proc/meminfo ]]; then
        echo "Total: $(utils::quiet_err grep MemTotal /proc/meminfo | awk '{print $2 $3}')"
        echo "Free: $(utils::quiet_err grep MemFree /proc/meminfo | awk '{print $2 $3}')"
        echo "Available: $(utils::quiet_err grep MemAvailable /proc/meminfo | awk '{print $2 $3}')"
        echo "Buffers: $(utils::quiet_err grep Buffers /proc/meminfo | awk '{print $2 $3}')"
        echo "Cached: $(utils::quiet_err grep -E '^Cached:' /proc/meminfo | awk '{print $2 $3}')"
        echo "Swap Total: $(utils::quiet_err grep SwapTotal /proc/meminfo | awk '{print $2 $3}')"
        echo "Swap Free: $(utils::quiet_err grep SwapFree /proc/meminfo | awk '{print $2 $3}')"
    else
        log::warn "Cannot determine memory information"
        return 1
    fi
}

# @description Get disk usage information / Получить информацию об использовании дисков
# @example
#   system::info::disk
system::info::disk() {
    echo "=== Disk Usage ==="
    
    if utils::has df; then
        utils::quiet_err df -h
        echo ""
        echo "Inodes:"
        utils::quiet_err df -i | head -10
    else
        log::warn "df command not found"
        return 1
    fi
}

# @description Get all system information / Получить всю системную информацию
# @example
#   system::info::all
system::info::all() {
    system::info::os
    echo ""
    system::info::kernel
    echo ""
    system::info::hostname
    echo ""
    system::info::uptime
    echo ""
    system::info::cpu
    echo ""
    system::info::memory
    echo ""
    system::info::disk
}

# @description Get distribution version
# @example
#   system::info::version
system::info::version() {
    # Try /etc/os-release first / Попробовать /etc/os-release сначала
    if [[ -f /etc/os-release ]]; then
        # Read in a subshell to avoid polluting current environment
        # Читаем в подshell, чтобы не засорять текущее окружение
        (
            source /etc/os-release
            echo "${PRETTY_NAME:-${NAME:-Unknown}} ${VERSION_ID:-Unknown}"
        )
    # Try lsb_release / Попробовать lsb_release
    elif utils::has lsb_release; then
        utils::quiet_err lsb_release -d | cut -f2
    # Fallback to uname / Резервный вариант uname
    elif utils::has uname; then
        utils::quiet_err uname -r
    else
        echo "Unknown"
        return 1
    fi
}

# @description Get system load average
# @example
#   system::info::load
system::info::load() {
    echo "=== System Load Average ==="
    
    if utils::has uptime; then
        utils::quiet_err uptime | awk -F'load average:' '{print $2}'
    # Fallback to /proc/loadavg / Резервный вариант /proc/loadavg
    elif [[ -r /proc/loadavg ]]; then
        local load
        load=$(utils::quiet_err cat /proc/loadavg)
        echo "1 min: $(echo ${load} | awk '{print $1}')"
        echo "5 min: $(echo ${load} | awk '{print $2}')"
        echo "15 min: $(echo ${load} | awk '{print $3}')"
    else
        log::warn "Cannot determine load average"
        return 1
    fi
}

# @description Get network interfaces information
# @example
#   system::info::interfaces
system::info::interfaces() {
    echo "=== Network Interfaces ==="
    
    # Try ip command (modern) / Попробовать команду ip (современная)
    if utils::has ip; then
        utils::quiet_err ip addr show
    # Fallback to ifconfig / Резервный вариант ifconfig
    elif utils::has ifconfig; then
        utils::quiet_err ifconfig
    else
        log::warn "Cannot show network interfaces (ip/ifconfig not found)"
        return 1
    fi
}

# @description Get system architecture
# @example
#   system::info::arch
system::info::arch() {
    if utils::has uname; then
        utils::quiet_err uname -m
    elif utils::has arch; then
        utils::quiet_err arch
    else
        log::warn "Cannot determine architecture"
        return 1
    fi
}

