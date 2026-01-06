#!/usr/bin/env bs
# info.sh — System information for system setup / Системная информация для настройки
# системы

# @description Get operating system information / Получить информацию об операционной
# системе
# @example
#   system::info::os
system::info::os() {
    echo "=== Operating System ==="
    
    # Try /etc/os-release first (modern standard) / Попробовать /etc/os-release сначала
    # (современный стандарт)
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "Name: ${NAME:-Unknown}"
        echo "Version: ${VERSION:-Unknown}"
        echo "ID: ${ID:-Unknown}"
        echo "ID_LIKE: ${ID_LIKE:-Unknown}"
        echo "Version ID: ${VERSION_ID:-Unknown}"
        echo "Pretty Name: ${PRETTY_NAME:-Unknown}"
    # Fallback to lsb_release / Резервный вариант lsb_release
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -a 2>/dev/null
    # Fallback to uname / Резервный вариант uname
    elif command -v uname >/dev/null 2>&1; then
        uname -a 2>/dev/null
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
    
    if command -v uname >/dev/null 2>&1; then
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
    
    if command -v hostname >/dev/null 2>&1; then
        echo "Hostname: $(hostname 2>/dev/null)"
        echo "FQDN: $(hostname -f 2>/dev/null || hostname)"
        echo "Short: $(hostname -s 2>/dev/null || hostname)"
    # Try hostnamectl (systemd) / Попробовать hostnamectl (systemd)
    elif command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl 2>/dev/null
    # Fallback to /etc/hostname / Резервный вариант /etc/hostname
    elif [[ -f /etc/hostname ]]; then
        echo "Hostname: $(cat /etc/hostname 2>/dev/null)"
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
    
    if command -v uptime >/dev/null 2>&1; then
        uptime 2>/dev/null
    # Fallback to /proc/uptime / Резервный вариант /proc/uptime
    elif [[ -r /proc/uptime ]]; then
        local uptime_seconds
        uptime_seconds=$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)
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
        echo "Model: $(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//')"
        echo "Cores: $(grep -c "^processor" /proc/cpuinfo 2>/dev/null)"
        echo "Physical CPUs: $(grep "physical id" /proc/cpuinfo 2>/dev/null | sort -u | wc -l)"
        echo "CPU MHz: $(grep -m1 "cpu MHz" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//')"
        echo "Cache: $(grep -m1 "cache size" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//')"
    # Try lscpu (modern alternative) / Попробовать lscpu (современная альтернатива)
    elif command -v lscpu >/dev/null 2>&1; then
        lscpu 2>/dev/null
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
    if command -v free >/dev/null 2>&1; then
        free -h 2>/dev/null
        echo ""
        echo "Detailed:"
        free -m 2>/dev/null
    # Fallback to /proc/meminfo / Резервный вариант /proc/meminfo
    elif [[ -r /proc/meminfo ]]; then
        echo "Total: $(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2 $3}')"
        echo "Free: $(grep MemFree /proc/meminfo 2>/dev/null | awk '{print $2 $3}')"
        echo "Available: $(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2 $3}')"
        echo "Buffers: $(grep Buffers /proc/meminfo 2>/dev/null | awk '{print $2 $3}')"
        echo "Cached: $(grep -E '^Cached:' /proc/meminfo 2>/dev/null | awk '{print $2 $3}')"
        echo "Swap Total: $(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2 $3}')"
        echo "Swap Free: $(grep SwapFree /proc/meminfo 2>/dev/null | awk '{print $2 $3}')"
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
    
    if command -v df >/dev/null 2>&1; then
        df -h 2>/dev/null
        echo ""
        echo "Inodes:"
        df -i 2>/dev/null | head -10
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
        source /etc/os-release
        echo "${PRETTY_NAME:-${NAME:-Unknown}} ${VERSION_ID:-Unknown}"
    # Try lsb_release / Попробовать lsb_release
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -d 2>/dev/null | cut -f2
    # Fallback to uname / Резервный вариант uname
    elif command -v uname >/dev/null 2>&1; then
        uname -r 2>/dev/null
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
    
    if command -v uptime >/dev/null 2>&1; then
        uptime 2>/dev/null | awk -F'load average:' '{print $2}'
    # Fallback to /proc/loadavg / Резервный вариант /proc/loadavg
    elif [[ -r /proc/loadavg ]]; then
        local load
        load=$(cat /proc/loadavg 2>/dev/null)
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
    if command -v ip >/dev/null 2>&1; then
        ip addr show 2>/dev/null
    # Fallback to ifconfig / Резервный вариант ifconfig
    elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig 2>/dev/null
    else
        log::warn "Cannot show network interfaces (ip/ifconfig not found)"
        return 1
    fi
}

# @description Get system architecture
# @example
#   system::info::arch
system::info::arch() {
    if command -v uname >/dev/null 2>&1; then
        uname -m 2>/dev/null
    elif command -v arch >/dev/null 2>&1; then
        arch 2>/dev/null
    else
        log::warn "Cannot determine architecture"
        return 1
    fi
}

