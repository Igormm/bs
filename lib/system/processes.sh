#!/usr/bin/env bs
# processes.sh — Process management for system setup / Управление процессами для настройки
# системы

# @description List all running processes / Показать все запущенные процессы
# @example
#   system::processes::list
system::processes::list() {
    if command -v ps >/dev/null 2>&1; then
        # Modern ps with wide output / Современный ps с широким выводом
        if ps aux 2>/dev/null | head -1; then
            ps aux 2>/dev/null | tail -n +2
        # Fallback to basic ps / Резервный вариант базового ps
        else
            ps -ef 2>/dev/null
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
    
    if command -v pgrep >/dev/null 2>&1; then
        local pids
        pids=$(pgrep -f "${pattern}" 2>/dev/null)
        if [[ -n "${pids}" ]]; then
            ps -p "${pids}" -o pid,user,comm,args 2>/dev/null
        else
            log::info "No processes found matching '${pattern}'"
            return 1
        fi
    elif command -v ps >/dev/null 2>&1; then
        ps aux 2>/dev/null | grep -i "${pattern}" | grep -v grep
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
    if ! ps -p "${pid}" >/dev/null 2>&1; then
        log::warn "Process ${pid} does not exist"
        return 1
    fi
    
    if command -v kill >/dev/null 2>&1; then
        if kill -${signal} "${pid}" 2>/dev/null; then
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
    if command -v pgrep >/dev/null 2>&1; then
        pids=$(pgrep -f "${pattern}" 2>/dev/null)
    elif command -v pidof >/dev/null 2>&1; then
        pids=$(pidof "${pattern}" 2>/dev/null)
    else
        # Fallback using ps and grep / Резервный вариант с использованием ps и grep
        pids=$(ps aux 2>/dev/null | grep -i "${pattern}" | grep -v grep | awk '{print $2}')
    fi
    
    if [[ -z "${pids}" ]]; then
        log::warn "No processes found matching '${pattern}'"
        return 1
    fi
    
    local killed=0
    for pid in ${pids}; do
        if system::processes::kill "${pid}" "${signal}" 2>/dev/null; then
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
    if command -v pstree >/dev/null 2>&1; then
        pstree -p 2>/dev/null
    elif command -v ps >/dev/null 2>&1; then
        # Simple tree using ps / Простое дерево с использованием ps
        ps auxf 2>/dev/null | head -20
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
    
    if command -v top >/dev/null 2>&1; then
        top -bn1 | head -n $((count + 7)) | tail -n +8 2>/dev/null
    elif command -v ps >/dev/null 2>&1; then
        ps aux --sort=-%cpu 2>/dev/null | head -n $((count + 1)) | tail -n +2
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
    
    if command -v top >/dev/null 2>&1; then
        top -bn1 -o %MEM | head -n $((count + 7)) | tail -n +8 2>/dev/null
    elif command -v ps >/dev/null 2>&1; then
        ps aux --sort=-%mem 2>/dev/null | head -n $((count + 1)) | tail -n +2
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
    if command -v lsof >/dev/null 2>&1; then
        local result
        result=$(lsof -i :"${port}" 2>/dev/null)
        if [[ -n "${result}" ]]; then
            echo "${result}"
            return 0
        else
            log::info "No process found using port ${port}"
            return 1
        fi
    # Try netstat / Попробовать netstat
    elif command -v netstat >/dev/null 2>&1; then
        local result
        result=$(netstat -tulpn 2>/dev/null | grep ":${port} ")
        if [[ -n "${result}" ]]; then
            echo "${result}"
            return 0
        else
            log::info "No process found using port ${port}"
            return 1
        fi
    # Try ss (modern replacement for netstat) / Попробовать ss (современная замена
    # netstat)
    elif command -v ss >/dev/null 2>&1; then
        local result
        result=$(ss -tulpn 2>/dev/null | grep ":${port} ")
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
    if ! ps -p "${pid}" >/dev/null 2>&1; then
        log::warn "Process ${pid} does not exist"
        return 1
    fi
    
    if command -v ps >/dev/null 2>&1; then
        echo "=== Process Information (PID: ${pid}) ==="
        ps -p "${pid}" -o pid,ppid,user,comm,cmd,etime,%cpu,%mem,stat 2>/dev/null
    fi
    
    # Additional info from /proc if available / Дополнительная информация из /proc если
    # доступна
    if [[ -d "/proc/${pid}" ]]; then
        if [[ -r "/proc/${pid}/cmdline" ]]; then
            echo ""
            echo "Command line:"
            cat /proc/${pid}/cmdline 2>/dev/null | tr '\0' ' ' && echo
        fi
        
        if [[ -r "/proc/${pid}/environ" ]]; then
            echo ""
            echo "Environment variables (first 5):"
            cat /proc/${pid}/environ 2>/dev/null | tr '\0' '\n' | head -5
        fi
    fi
}

