#!/usr/bin/env bs
# processes.sh — Process management for system setup / Управление процессами для настройки
# системы
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "SYSTEM_PROCESSES" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @description List all running processes / Показать все запущенные процессы
# @example
#   system::processes::list
system::processes::list() {
    if utils::has ps; then
        # Modern ps with wide output / Современный ps с широким выводом
        if utils::quiet_err ps aux | head -1; then
            utils::quiet_err ps aux | tail -n +2
        # Fallback to basic ps / Резервный вариант базового ps
        else
            utils::quiet_err ps -ef
        fi
    else
        log::error "ps command not found"
        return 1
    fi
}

# @description Find processes by name / Найти процессы по имени
# @param $1 Process name or pattern / Имя процесса или шаблон
# @example
#   system::processes::find "apache"
system::processes::find() {
    local pattern="${1}"
    
    if [[ -z "${pattern}" ]]; then
        log::warn "Process name/pattern not specified"
        return 1
    fi
    
    if utils::has pgrep; then
        local pids
        pids=$(utils::quiet_err pgrep -f "${pattern}")
        if [[ -n "${pids}" ]]; then
            utils::quiet_err ps -p "${pids}" -o pid,user,comm,args
        else
            log::info "No processes found matching '${pattern}'"
            return 1
        fi
    elif utils::has ps; then
        utils::quiet_err ps aux | grep -i "${pattern}" | grep -v grep
    else
        log::error "pgrep or ps command not found"
        return 1
    fi
}

# @description Kill a process by PID / Завершить процесс по PID
# @param $1 Process ID / Идентификатор процесса
# @param $2 [optional] Signal (default: TERM) / [опционально] Сигнал (по умолчанию: TERM)
# @example
#   system::processes::kill "1234"
#   system::processes::kill "1234" "KILL"
system::processes::kill() {
    local pid="${1}"
    local signal="${2:-TERM}"
    
    if [[ -z "${pid}" ]]; then
        log::warn "Process ID not specified"
        return 1
    fi
    
    # Check if process exists
    if ! utils::quiet ps -p "${pid}"; then
        log::warn "Process ${pid} does not exist"
        return 1
    fi
    
    if utils::has kill; then
        if utils::quiet_err kill -${signal} "${pid}"; then
            log::info "Sent ${signal} signal to process ${pid}"
            return 0
        else
            log::error "Failed to kill process ${pid}"
            return 1
        fi
    else
        log::error "kill command not found"
        return 1
    fi
}

# @description Kill processes by name / Завершить процессы по имени
# @param $1 Process name or pattern / Имя процесса или шаблон
# @param $2 [optional] Signal (default: TERM) / [опционально] Сигнал (по умолчанию: TERM)
# @example
#   system::processes::kill_by_name "apache"
#   system::processes::kill_by_name "python" "KILL"
system::processes::kill_by_name() {
    local pattern="${1}"
    local signal="${2:-TERM}"
    
    if [[ -z "${pattern}" ]]; then
        log::warn "Process name/pattern not specified"
        return 1
    fi
    
    local pids
    if utils::has pgrep; then
        pids=$(utils::quiet_err pgrep -f "${pattern}")
    elif utils::has pidof; then
        pids=$(utils::quiet_err pidof "${pattern}")
    else
        # Fallback using ps and grep / Резервный вариант с использованием ps и grep
        pids=$(utils::quiet_err ps aux | grep -i "${pattern}" | grep -v grep | awk '{print $2}')
    fi
    
    if [[ -z "${pids}" ]]; then
        log::warn "No processes found matching '${pattern}'"
        return 1
    fi
    
    local killed=0
    for pid in ${pids}; do
        if utils::quiet_err system::processes::kill "${pid}" "${signal}"; then
            killed=$((killed + 1))
        fi
    done
    
    if [[ ${killed} -gt 0 ]]; then
        log::info "Killed ${killed} process(es) matching '${pattern}'"
        return 0
    else
        log::error "Failed to kill any processes matching '${pattern}'"
        return 1
    fi
}

# @description Show process tree / Показать дерево процессов
# @example
#   system::processes::tree
system::processes::tree() {
    if utils::has pstree; then
        utils::quiet_err pstree -p
    elif utils::has ps; then
        # Simple tree using ps / Простое дерево с использованием ps
        utils::quiet_err ps auxf | head -20
        log::info "Full tree view requires pstree command"
    else
        log::error "pstree or ps command not found"
        return 1
    fi
}

# @description Show top processes by CPU usage
# @param $1 [optional] Number of processes (default: 10)
# @example
#   system::processes::cpu_top
#   system::processes::cpu_top 5
system::processes::cpu_top() {
    local count="${1:-10}"
    
    if utils::has top; then
        top -bn1 | head -n $((count + 7)) | utils::quiet_err tail -n +8
    elif utils::has ps; then
        utils::quiet_err ps aux --sort=-%cpu | head -n $((count + 1)) | tail -n +2
    else
        log::error "top or ps command not found"
        return 1
    fi
}

# @description Show top processes by memory usage
# @param $1 [optional] Number of processes (default: 10)
# @example
#   system::processes::memory_top
#   system::processes::memory_top 5
system::processes::memory_top() {
    local count="${1:-10}"
    
    if utils::has top; then
        top -bn1 -o %MEM | head -n $((count + 7)) | utils::quiet_err tail -n +8
    elif utils::has ps; then
        utils::quiet_err ps aux --sort=-%mem | head -n $((count + 1)) | tail -n +2
    else
        log::error "top or ps command not found"
        return 1
    fi
}

# @description Find process using a specific port
# @param $1 Port number
# @example
#   system::processes::port "8080"
system::processes::port() {
    local port="${1}"
    
    if [[ -z "${port}" ]]; then
        log::warn "Port number not specified"
        return 1
    fi
    
    # Try lsof first / Попробовать lsof сначала
    if utils::has lsof; then
        local result
        result=$(utils::quiet_err lsof -i :"${port}")
        if [[ -n "${result}" ]]; then
            echo "${result}"
            return 0
        else
            log::info "No process found using port ${port}"
            return 1
        fi
    # Try netstat / Попробовать netstat
    elif utils::has netstat; then
        local result
        result=$(utils::quiet_err netstat -tulpn | grep ":${port} ")
        if [[ -n "${result}" ]]; then
            echo "${result}"
            return 0
        else
            log::info "No process found using port ${port}"
            return 1
        fi
    # Try ss (modern replacement for netstat) / Попробовать ss (современная замена
    # netstat)
    elif utils::has ss; then
        local result
        result=$(utils::quiet_err ss -tulpn | grep ":${port} ")
        if [[ -n "${result}" ]]; then
            echo "${result}"
            return 0
        else
            log::info "No process found using port ${port}"
            return 1
        fi
    else
        log::error "lsof, netstat, or ss command not found"
        return 1
    fi
}

# @description Get detailed information about a process
# @param $1 Process ID
# @example
#   system::processes::info "1234"
system::processes::info() {
    local pid="${1}"
    
    if [[ -z "${pid}" ]]; then
        log::warn "Process ID not specified"
        return 1
    fi
    
    # Check if process exists / Проверить, существует ли процесс
    if ! utils::quiet ps -p "${pid}"; then
        log::warn "Process ${pid} does not exist"
        return 1
    fi
    
    if utils::has ps; then
        echo "=== Process Information (PID: ${pid}) ==="
        utils::quiet_err ps -p "${pid}" -o pid,ppid,user,comm,cmd,etime,%cpu,%mem,stat
    fi
    
    # Additional info from /proc if available / Дополнительная информация из /proc если
    # доступна
    if [[ -d "/proc/${pid}" ]]; then
        if [[ -r "/proc/${pid}/cmdline" ]]; then
            echo ""
            echo "Command line:"
            utils::quiet_err cat /proc/${pid}/cmdline | tr '\0' ' ' && echo
        fi
        
        if [[ -r "/proc/${pid}/environ" ]]; then
            echo ""
            echo "Environment variables (first 5):"
            utils::quiet_err cat /proc/${pid}/environ | tr '\0' '\n' | head -5
        fi
    fi
}

