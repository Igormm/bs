#!/usr/bin/env bs

#
# BS Framework - Enhanced Bash Scripting
# Фреймворк BS - Расширенное bash-скриптование
#
# НАЗНАЧЕНИЕ: Главный entrypoint фреймворка BS
# PURPOSE: Main entrypoint for BS framework
#
# ЗАВИСИМОСТИ: bash 4.0+, стандартные утилиты Linux
# DEPENDENCIES: bash 4.0+, standard Linux utilities
#
# ИСПОЛЬЗУЕТСЯ: Для инициализации фреймворка и загрузки модулей
# USAGE: For framework initialization and module loading
#
# shellcheck disable=SC2155



# ps1status.sh — PS1 Status Monitoring Module for BS Framework

# Модуль мониторинга статуса PS1 для фреймворка BS

#

# Description:

#   Provides real-time PS1 prompt status indicators for:

#   - WireGuard connection status

#   - Network connectivity status

#   - Internet speed monitoring

#   - Audio equalizer status

#   - Modular components that can be enabled/disabled

#

# Features:

#   - Real-time status updates

#   - Modular component system

#   - Customizable indicators

#   - Performance optimized

#   - Cross-platform support

#

# @author BS Framework

# @since 2026-01-06

# @version 1.0.0



# Check if module is already loaded

if [[ -n "${BOSA_LIB_STATUS_PS1_LOADED:-}" ]]; then

    log::debug "PS1 Status module already loaded" 2>/dev/null || true

    return 0

fi

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly BOSA_LIB_STATUS_PS1_LOADED - [Описание переменной]
# readonly BOSA_LIB_STATUS_PS1_LOADED - [Variable description]
#
readonly BOSA_LIB_STATUS_PS1_LOADED=1



# Import required modules

#
# ПОДКЛЮЧЕНИЕ МОДУЛЯ / MODULE IMPORT:
# Импортируется: "${BS_HOME}/core/const.sh"
# Imports: "${BS_HOME}/core/const.sh"
#
source "${BS_HOME}/core/const.sh"

#
# ПОДКЛЮЧЕНИЕ МОДУЛЯ / MODULE IMPORT:
# Импортируется: "${BS_HOME}/core/logger.sh"
# Imports: "${BS_HOME}/core/logger.sh"
#
source "${BS_HOME}/core/logger.sh"

#
# ПОДКЛЮЧЕНИЕ МОДУЛЯ / MODULE IMPORT:
# Импортируется: "${BS_HOME}/core/errorhandler.sh"
# Imports: "${BS_HOME}/core/errorhandler.sh"
#
source "${BS_HOME}/core/errorhandler.sh"



# PS1 Status configuration

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_CONFIG_DIR - [Описание переменной]
# readonly PS1_STATUS_CONFIG_DIR - [Variable description]
#
readonly PS1_STATUS_CONFIG_DIR="${HOME}/.config/ps1status"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_CACHE_DIR - [Описание переменной]
# readonly PS1_STATUS_CACHE_DIR - [Variable description]
#
readonly PS1_STATUS_CACHE_DIR="/tmp/ps1_status_cache"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_UPDATE_INTERVAL - [Описание переменной]
# readonly PS1_STATUS_UPDATE_INTERVAL - [Variable description]
#
readonly PS1_STATUS_UPDATE_INTERVAL=5  # seconds



# Status components state

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_COMPONENTS - [Описание переменной]
# PS1_STATUS_COMPONENTS - [Variable description]
#
PS1_STATUS_COMPONENTS=(

    "wireguard"

    "network"

    "speed"

    "audio"

    "system"

)



#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_ENABLED_COMPONENTS - [Описание переменной]
# PS1_STATUS_ENABLED_COMPONENTS - [Variable description]
#
PS1_STATUS_ENABLED_COMPONENTS=(

    "wireguard"

    "network"

    "system"

)



# Color definitions for status indicators

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_COLOR_WIREGUARD_UP - [Описание переменной]
# readonly PS1_STATUS_COLOR_WIREGUARD_UP - [Variable description]
#
readonly PS1_STATUS_COLOR_WIREGUARD_UP="\033[0;32m"    # Green

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_COLOR_WIREGUARD_DOWN - [Описание переменной]
# readonly PS1_STATUS_COLOR_WIREGUARD_DOWN - [Variable description]
#
readonly PS1_STATUS_COLOR_WIREGUARD_DOWN="\033[0;31m"  # Red

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_COLOR_NETWORK_UP - [Описание переменной]
# readonly PS1_STATUS_COLOR_NETWORK_UP - [Variable description]
#
readonly PS1_STATUS_COLOR_NETWORK_UP="\033[0;32m"      # Green

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_COLOR_NETWORK_DOWN - [Описание переменной]
# readonly PS1_STATUS_COLOR_NETWORK_DOWN - [Variable description]
#
readonly PS1_STATUS_COLOR_NETWORK_DOWN="\033[0;31m"    # Red

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_COLOR_SPEED_GOOD - [Описание переменной]
# readonly PS1_STATUS_COLOR_SPEED_GOOD - [Variable description]
#
readonly PS1_STATUS_COLOR_SPEED_GOOD="\033[0;32m"      # Green

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_COLOR_SPEED_MEDIUM - [Описание переменной]
# readonly PS1_STATUS_COLOR_SPEED_MEDIUM - [Variable description]
#
readonly PS1_STATUS_COLOR_SPEED_MEDIUM="\033[0;33m"    # Yellow

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_COLOR_SPEED_SLOW - [Описание переменной]
# readonly PS1_STATUS_COLOR_SPEED_SLOW - [Variable description]
#
readonly PS1_STATUS_COLOR_SPEED_SLOW="\033[0;31m"      # Red

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_COLOR_AUDIO_ON - [Описание переменной]
# readonly PS1_STATUS_COLOR_AUDIO_ON - [Variable description]
#
readonly PS1_STATUS_COLOR_AUDIO_ON="\033[0;35m"        # Magenta

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_COLOR_AUDIO_OFF - [Описание переменной]
# readonly PS1_STATUS_COLOR_AUDIO_OFF - [Variable description]
#
readonly PS1_STATUS_COLOR_AUDIO_OFF="\033[0;37m"       # Gray

#
# ПЕРЕМЕННАЯ / VARIABLE:
# readonly PS1_STATUS_COLOR_RESET - [Описание переменной]
# readonly PS1_STATUS_COLOR_RESET - [Variable description]
#
readonly PS1_STATUS_COLOR_RESET="\033[0m"              # Reset



# Module initialization

ps1status::init() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::init"

    

    log::info "Initializing PS1 Status module..."

    

    # Create necessary directories

    mkdir -p "${PS1_STATUS_CONFIG_DIR}" || {

        errorhandler::throw "${func_name}" "Failed to create config directory" \

            "${LIB_ERROR_FILE_OPERATION}"

    }

    

    mkdir -p "${PS1_STATUS_CACHE_DIR}" || {

        errorhandler::throw "${func_name}" "Failed to create cache directory" \

            "${LIB_ERROR_FILE_OPERATION}"

    }

    

    # Check dependencies

    ps1status::check_dependencies

    

    # Initialize components

    ps1status::init_components

    

    # Start background monitoring if not already running

    ps1status::start_monitoring

    

    log::success "PS1 Status module initialized successfully"

}



# Check dependencies

ps1status::check_dependencies() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::check_dependencies"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# missing_deps - локальная переменная для этой функции
# missing_deps - local variable for this function
#
    local missing_deps=()

    

    log::debug "Checking PS1 Status dependencies..."

    

    # Check for basic network tools

    if ! command -v ping >/dev/null 2>&1; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# missing_deps+ - [Описание переменной]
# missing_deps+ - [Variable description]
#
        missing_deps+=("iputils-ping")

    fi

    

    if ! command -v curl >/dev/null 2>&1; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# missing_deps+ - [Описание переменной]
# missing_deps+ - [Variable description]
#
        missing_deps+=("curl")

    fi

    

    if ! command -v wg >/dev/null 2>&1; then

        log::debug "WireGuard tools not found - WireGuard status will be disabled"

    fi

    

    if ! command -v pactl >/dev/null 2>&1 && ! command -v amixer >/dev/null 2>&1; then

        log::debug "Audio tools not found - Audio status will be disabled"

    fi

    

    # Install missing dependencies

    if [[ ${#missing_deps[@]} -gt 0 ]]; then

        log::warn "Missing dependencies: ${missing_deps[*]}"

        ps1status::install_dependencies "${missing_deps[@]}"

    else

        log::debug "All basic dependencies are installed"

    fi

}



# Install dependencies

ps1status::install_dependencies() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::install_dependencies"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# deps - локальная переменная для этой функции
# deps - local variable for this function
#
    local deps=("$@")

    

    log::info "Installing missing dependencies: ${deps[*]}..."

    

    # Source platform check module

#
# ПОДКЛЮЧЕНИЕ МОДУЛЯ / MODULE IMPORT:
# Импортируется: "${BS_HOME}/lib/system/platformcheck.sh"
# Imports: "${BS_HOME}/lib/system/platformcheck.sh"
#
    source "${BS_HOME}/lib/system/platformcheck.sh"

    

    if platformcheck::is_debian || platformcheck::is_ubuntu; then

        apt-get update

        apt-get install -y curl iputils-ping

    elif platformcheck::is_alma || platformcheck::is_fedora; then

        dnf install -y curl iputils

    elif platformcheck::is_macos; then

        if ! command -v brew >/dev/null 2>&1; then

            errorhandler::throw "${func_name}" "Homebrew is required for macOS" \

                "${LIB_ERROR_DEPENDENCY_MISSING}"

        fi

        brew install curl

    else

        errorhandler::throw "${func_name}" "Unsupported platform for dependency installation" \

            "${LIB_ERROR_PLATFORM_UNSUPPORTED}"

    fi

    

    log::success "Dependencies installed successfully"

}



# Initialize status components

ps1status::init_components() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::init_components"

    

    log::debug "Initializing PS1 status components..."

    

    # Initialize WireGuard status

    ps1status::wireguard::init

    

    # Initialize network status

    ps1status::network::init

    

    # Initialize speed monitoring

    ps1status::speed::init

    

    # Initialize audio status

    ps1status::audio::init

    

    # Initialize system status

    ps1status::system::init

    

    log::debug "All PS1 status components initialized"

}



# Start background monitoring

ps1status::start_monitoring() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::start_monitoring"

    

    # Check if monitoring is already running

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# monitor_pid - локальная переменная для этой функции
# monitor_pid - local variable for this function
#
    local monitor_pid

    monitor_pid=$(ps aux | grep "ps1status::monitor_loop" | grep -v grep | awk '{print $2}' || true)

    

    if [[ -n "${monitor_pid}" ]]; then

        log::debug "PS1 monitoring already running (PID: ${monitor_pid})"

        return 0

    fi

    

    # Start monitoring in background

    ps1status::monitor_loop &

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# bg_pid - локальная переменная для этой функции
# bg_pid - local variable for this function
#
    local bg_pid=$!

    

    # Save PID for management

    echo "${bg_pid}" > "${PS1_STATUS_CONFIG_DIR}/monitor.pid"

    

    log::info "PS1 monitoring started (PID: ${bg_pid})"

}



# Main monitoring loop

ps1status::monitor_loop() {

    while true; do

        # Update all enabled components

        for component in "${PS1_STATUS_ENABLED_COMPONENTS[@]}"; do

            "ps1status::${component}::update" 2>/dev/null || true

        done

        

        sleep "${PS1_STATUS_UPDATE_INTERVAL}"

    done

}



# Stop monitoring

ps1status::stop_monitoring() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::stop_monitoring"

    

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# pid_file - локальная переменная для этой функции
# pid_file - local variable for this function
#
    local pid_file="${PS1_STATUS_CONFIG_DIR}/monitor.pid"

    

    if [[ -f "${pid_file}" ]]; then

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# monitor_pid - локальная переменная для этой функции
# monitor_pid - local variable for this function
#
        local monitor_pid

#
# ПЕРЕМЕННАЯ / VARIABLE:
# monitor_pid - [Описание переменной]
# monitor_pid - [Variable description]
#
        monitor_pid=$(cat "${pid_file}")

        

        if kill "${monitor_pid}" 2>/dev/null; then

            rm -f "${pid_file}"

            log::info "PS1 monitoring stopped (PID: ${monitor_pid})"

        else

            log::warn "Failed to stop monitoring or process not found"

        fi

    else

        log::debug "No monitoring process found"

    fi

}



# ============================================================================

# WIREGUARD STATUS COMPONENT

# Компонент статуса WireGuard

# ============================================================================



ps1status::wireguard::init() {

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_WIREGUARD_INTERFACES - [Описание переменной]
# PS1_STATUS_WIREGUARD_INTERFACES - [Variable description]
#
    PS1_STATUS_WIREGUARD_INTERFACES=()

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_WIREGUARD_LAST_STATUS - [Описание переменной]
# PS1_STATUS_WIREGUARD_LAST_STATUS - [Variable description]
#
    PS1_STATUS_WIREGUARD_LAST_STATUS="unknown"

    

    # Find active WireGuard interfaces

    if command -v wg >/dev/null 2>&1; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# while IFS - [Описание переменной]
# while IFS - [Variable description]
#
        while IFS= read -r interface; do

            if [[ -n "${interface}" ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_WIREGUARD_INTERFACES+ - [Описание переменной]
# PS1_STATUS_WIREGUARD_INTERFACES+ - [Variable description]
#
                PS1_STATUS_WIREGUARD_INTERFACES+=("${interface}")

            fi

        done < <(wg show interfaces 2>/dev/null)

    fi

}



ps1status::wireguard::update() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::wireguard::update"

    

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# status - локальная переменная для этой функции
# status - local variable for this function
#
    local status="down"

    

    # Check if any WireGuard interface is up

    if [[ ${#PS1_STATUS_WIREGUARD_INTERFACES[@]} -gt 0 ]]; then

        for interface in "${PS1_STATUS_WIREGUARD_INTERFACES[@]}"; do

            if wg show "${interface}" >/dev/null 2>&1; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# status - [Описание переменной]
# status - [Variable description]
#
                status="up"

                break

            fi

        done

    fi

    

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_WIREGUARD_LAST_STATUS - [Описание переменной]
# PS1_STATUS_WIREGUARD_LAST_STATUS - [Variable description]
#
    PS1_STATUS_WIREGUARD_LAST_STATUS="${status}"

    

    # Cache the status

    echo "${status}" > "${PS1_STATUS_CACHE_DIR}/wireguard.status"

}



ps1status::wireguard::get_status() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# status_file - локальная переменная для этой функции
# status_file - local variable for this function
#
    local status_file="${PS1_STATUS_CACHE_DIR}/wireguard.status"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# status - локальная переменная для этой функции
# status - local variable for this function
#
    local status="down"

    

    if [[ -f "${status_file}" ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# status - [Описание переменной]
# status - [Variable description]
#
        status=$(cat "${status_file}")

    fi

    

    case "${status}" in

        up)

            echo -e "${PS1_STATUS_COLOR_WIREGUARD_UP}WG↑${PS1_STATUS_COLOR_RESET}"

            ;;

        down)

            echo -e "${PS1_STATUS_COLOR_WIREGUARD_DOWN}WG↓${PS1_STATUS_COLOR_RESET}"

            ;;

        *)

            echo -e "${PS1_STATUS_COLOR_WIREGUARD_DOWN}WG?${PS1_STATUS_COLOR_RESET}"

            ;;

    esac

}



# ============================================================================

# NETWORK STATUS COMPONENT

# Компонент статуса сети

# ============================================================================



ps1status::network::init() {

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_NETWORK_TEST_HOSTS - [Описание переменной]
# PS1_STATUS_NETWORK_TEST_HOSTS - [Variable description]
#
    PS1_STATUS_NETWORK_TEST_HOSTS=(

        "8.8.8.8"      # Google DNS

        "1.1.1.1"      # Cloudflare DNS

        "208.67.222.222" # OpenDNS

    )

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_NETWORK_LAST_STATUS - [Описание переменной]
# PS1_STATUS_NETWORK_LAST_STATUS - [Variable description]
#
    PS1_STATUS_NETWORK_LAST_STATUS="unknown"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_NETWORK_LAST_LATENCY - [Описание переменной]
# PS1_STATUS_NETWORK_LAST_LATENCY - [Variable description]
#
    PS1_STATUS_NETWORK_LAST_LATENCY="0"

}



ps1status::network::update() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::network::update"

    

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# status - локальная переменная для этой функции
# status - local variable for this function
#
    local status="down"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# total_latency - локальная переменная для этой функции
# total_latency - local variable for this function
#
    local total_latency=0

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# successful_pings - локальная переменная для этой функции
# successful_pings - local variable for this function
#
    local successful_pings=0

    

    # Test connectivity to multiple hosts

    for host in "${PS1_STATUS_NETWORK_TEST_HOSTS[@]}"; do

        if ping -c 1 -W 1 "${host}" >/dev/null 2>&1; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# status - [Описание переменной]
# status - [Variable description]
#
            status="up"

            ((successful_pings++))

            

            # Get latency

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# latency - локальная переменная для этой функции
# latency - local variable for this function
#
            local latency

            latency=$(ping -c 1 -W 1 "${host}" 2>/dev/null | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/' || echo "0")

            total_latency=$(echo "${total_latency} + ${latency}" | bc -l 2>/dev/null || echo "${total_latency}")

        fi

    done

    

    # Calculate average latency

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# avg_latency - локальная переменная для этой функции
# avg_latency - local variable for this function
#
    local avg_latency=0

    if [[ "${successful_pings}" -gt 0 ]]; then

        avg_latency=$(echo "scale=1; ${total_latency} / ${successful_pings}" | bc -l 2>/dev/null || echo "0")

    fi

    

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_NETWORK_LAST_STATUS - [Описание переменной]
# PS1_STATUS_NETWORK_LAST_STATUS - [Variable description]
#
    PS1_STATUS_NETWORK_LAST_STATUS="${status}"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_NETWORK_LAST_LATENCY - [Описание переменной]
# PS1_STATUS_NETWORK_LAST_LATENCY - [Variable description]
#
    PS1_STATUS_NETWORK_LAST_LATENCY="${avg_latency}"

    

    # Cache results

    echo "${status}" > "${PS1_STATUS_CACHE_DIR}/network.status"

    echo "${avg_latency}" > "${PS1_STATUS_CACHE_DIR}/network.latency"

}



ps1status::network::get_status() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# status_file - локальная переменная для этой функции
# status_file - local variable for this function
#
    local status_file="${PS1_STATUS_CACHE_DIR}/network.status"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# latency_file - локальная переменная для этой функции
# latency_file - local variable for this function
#
    local latency_file="${PS1_STATUS_CACHE_DIR}/network.latency"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# status - локальная переменная для этой функции
# status - local variable for this function
#
    local status="down"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# latency - локальная переменная для этой функции
# latency - local variable for this function
#
    local latency="0"

    

    if [[ -f "${status_file}" ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# status - [Описание переменной]
# status - [Variable description]
#
        status=$(cat "${status_file}")

    fi

    

    if [[ -f "${latency_file}" ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# latency - [Описание переменной]
# latency - [Variable description]
#
        latency=$(cat "${latency_file}")

    fi

    

    case "${status}" in

        up)

            if (( $(echo "${latency} < 50" | bc -l 2>/dev/null || echo "1") )); then

                echo -e "${PS1_STATUS_COLOR_NETWORK_UP}NET✓${PS1_STATUS_COLOR_RESET}"

            elif (( $(echo "${latency} < 100" | bc -l 2>/dev/null || echo "1") )); then

                echo -e "${PS1_STATUS_COLOR_SPEED_MEDIUM}NET~${PS1_STATUS_COLOR_RESET}"

            else

                echo -e "${PS1_STATUS_COLOR_SPEED_SLOW}NET!${PS1_STATUS_COLOR_RESET}"

            fi

            ;;

        down)

            echo -e "${PS1_STATUS_COLOR_NETWORK_DOWN}NET✗${PS1_STATUS_COLOR_RESET}"

            ;;

        *)

            echo -e "${PS1_STATUS_COLOR_NETWORK_DOWN}NET?${PS1_STATUS_COLOR_RESET}"

            ;;

    esac

}



# ============================================================================

# SPEED MONITORING COMPONENT

# Компонент мониторинга скорости

# ============================================================================



ps1status::speed::init() {

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SPEED_TEST_URL - [Описание переменной]
# PS1_STATUS_SPEED_TEST_URL - [Variable description]
#
    PS1_STATUS_SPEED_TEST_URL="https://speed.cloudflare.com/__down?bytes=1048576"  # 1MB

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SPEED_LAST_DOWNLOAD - [Описание переменной]
# PS1_STATUS_SPEED_LAST_DOWNLOAD - [Variable description]
#
    PS1_STATUS_SPEED_LAST_DOWNLOAD="0"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SPEED_LAST_UPLOAD - [Описание переменной]
# PS1_STATUS_SPEED_LAST_UPLOAD - [Variable description]
#
    PS1_STATUS_SPEED_LAST_UPLOAD="0"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SPEED_LAST_TEST - [Описание переменной]
# PS1_STATUS_SPEED_LAST_TEST - [Variable description]
#
    PS1_STATUS_SPEED_LAST_TEST=0

}



ps1status::speed::update() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::speed::update"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# current_time - локальная переменная для этой функции
# current_time - local variable for this function
#
    local current_time=$(date +%s)

    

    # Only test speed every 5 minutes to avoid excessive testing

    if (( current_time - PS1_STATUS_SPEED_LAST_TEST < 300 )); then

        return 0

    fi

    

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SPEED_LAST_TEST - [Описание переменной]
# PS1_STATUS_SPEED_LAST_TEST - [Variable description]
#
    PS1_STATUS_SPEED_LAST_TEST="${current_time}"

    

    # Quick speed test (download only for performance)

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# start_time - локальная переменная для этой функции
# start_time - local variable for this function
#
    local start_time=$(date +%s.%N)

    

    if curl -s -o /dev/null --max-time 10 "${PS1_STATUS_SPEED_TEST_URL}" 2>/dev/null; then

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# end_time - локальная переменная для этой функции
# end_time - local variable for this function
#
        local end_time=$(date +%s.%N)

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# duration - локальная переменная для этой функции
# duration - local variable for this function
#
        local duration=$(echo "${end_time} - ${start_time}" | bc -l 2>/dev/null || echo "1")

        

        # Calculate speed in Mbps

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# speed - локальная переменная для этой функции
# speed - local variable for this function
#
        local speed=$(echo "scale=1; 8 / ${duration}" | bc -l 2>/dev/null || echo "0")

        

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SPEED_LAST_DOWNLOAD - [Описание переменной]
# PS1_STATUS_SPEED_LAST_DOWNLOAD - [Variable description]
#
        PS1_STATUS_SPEED_LAST_DOWNLOAD="${speed}"

    else

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SPEED_LAST_DOWNLOAD - [Описание переменной]
# PS1_STATUS_SPEED_LAST_DOWNLOAD - [Variable description]
#
        PS1_STATUS_SPEED_LAST_DOWNLOAD="0"

    fi

    

    # Cache result

    echo "${PS1_STATUS_SPEED_LAST_DOWNLOAD}" > "${PS1_STATUS_CACHE_DIR}/speed.download"

}



ps1status::speed::get_status() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# speed_file - локальная переменная для этой функции
# speed_file - local variable for this function
#
    local speed_file="${PS1_STATUS_CACHE_DIR}/speed.download"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# speed - локальная переменная для этой функции
# speed - local variable for this function
#
    local speed="0"

    

    if [[ -f "${speed_file}" ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# speed - [Описание переменной]
# speed - [Variable description]
#
        speed=$(cat "${speed_file}")

    fi

    

    if (( $(echo "${speed} > 50" | bc -l 2>/dev/null || echo "0") )); then

        echo -e "${PS1_STATUS_COLOR_SPEED_GOOD}↓${speed}M${PS1_STATUS_COLOR_RESET}"

    elif (( $(echo "${speed} > 10" | bc -l 2>/dev/null || echo "0") )); then

        echo -e "${PS1_STATUS_COLOR_SPEED_MEDIUM}↓${speed}M${PS1_STATUS_COLOR_RESET}"

    elif (( $(echo "${speed} > 0" | bc -l 2>/dev/null || echo "0") )); then

        echo -e "${PS1_STATUS_COLOR_SPEED_SLOW}↓${speed}M${PS1_STATUS_COLOR_RESET}"

    else

        echo -e "${PS1_STATUS_COLOR_NETWORK_DOWN}↓?M${PS1_STATUS_COLOR_RESET}"

    fi

}



# ============================================================================

# AUDIO STATUS COMPONENT

# Компонент статуса аудио

# ============================================================================



ps1status::audio::init() {

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_AUDIO_LAST_STATUS - [Описание переменной]
# PS1_STATUS_AUDIO_LAST_STATUS - [Variable description]
#
    PS1_STATUS_AUDIO_LAST_STATUS="unknown"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_AUDIO_LAST_VOLUME - [Описание переменной]
# PS1_STATUS_AUDIO_LAST_VOLUME - [Variable description]
#
    PS1_STATUS_AUDIO_LAST_VOLUME="0"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_AUDIO_LAST_MUTED - [Описание переменной]
# PS1_STATUS_AUDIO_LAST_MUTED - [Variable description]
#
    PS1_STATUS_AUDIO_LAST_MUTED="false"

}



ps1status::audio::update() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::audio::update"

    

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# volume - локальная переменная для этой функции
# volume - local variable for this function
#
    local volume="0"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# muted - локальная переменная для этой функции
# muted - local variable for this function
#
    local muted="false"

    

    # Try PulseAudio first

    if command -v pactl >/dev/null 2>&1; then

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# sink_info - локальная переменная для этой функции
# sink_info - local variable for this function
#
        local sink_info

        sink_info=$(pactl info 2>/dev/null | grep "Default Sink" | cut -d: -f2 | xargs)

        

        if [[ -n "${sink_info}" ]]; then

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# sink_volume - локальная переменная для этой функции
# sink_volume - local variable for this function
#
            local sink_volume

            sink_volume=$(pactl list sinks 2>/dev/null | grep -A 10 "${sink_info}" | grep "Volume:" | head -1)

            

            # Extract volume percentage

            if [[ -n "${sink_volume}" ]]; then

                volume=$(echo "${sink_volume}" | sed 's/.*\([0-9]*\)%.*/\1/' || echo "0")

            fi

            

            # Check if muted

            if pactl list sinks 2>/dev/null | grep -A 10 "${sink_info}" | grep -q "Mute: yes"; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# muted - [Описание переменной]
# muted - [Variable description]
#
                muted="true"

            fi

        fi

    # Fallback to ALSA

    elif command -v amixer >/dev/null 2>&1; then

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# mixer_info - локальная переменная для этой функции
# mixer_info - local variable for this function
#
        local mixer_info

        mixer_info=$(amixer get Master 2>/dev/null || amixer get PCM 2>/dev/null)

        

        if [[ -n "${mixer_info}" ]]; then

            # Extract volume

            volume=$(echo "${mixer_info}" | grep -o "[0-9]*%" | head -1 | tr -d '%' || echo "0")

            

            # Check if muted

            if echo "${mixer_info}" | grep -q "\[off\]"; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# muted - [Описание переменной]
# muted - [Variable description]
#
                muted="true"

            fi

        fi

    fi

    

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_AUDIO_LAST_VOLUME - [Описание переменной]
# PS1_STATUS_AUDIO_LAST_VOLUME - [Variable description]
#
    PS1_STATUS_AUDIO_LAST_VOLUME="${volume}"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_AUDIO_LAST_MUTED - [Описание переменной]
# PS1_STATUS_AUDIO_LAST_MUTED - [Variable description]
#
    PS1_STATUS_AUDIO_LAST_MUTED="${muted}"

    

    # Cache results

    echo "${volume}" > "${PS1_STATUS_CACHE_DIR}/audio.volume"

    echo "${muted}" > "${PS1_STATUS_CACHE_DIR}/audio.muted"

}



ps1status::audio::get_status() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# volume_file - локальная переменная для этой функции
# volume_file - local variable for this function
#
    local volume_file="${PS1_STATUS_CACHE_DIR}/audio.volume"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# muted_file - локальная переменная для этой функции
# muted_file - local variable for this function
#
    local muted_file="${PS1_STATUS_CACHE_DIR}/audio.muted"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# volume - локальная переменная для этой функции
# volume - local variable for this function
#
    local volume="0"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# muted - локальная переменная для этой функции
# muted - local variable for this function
#
    local muted="false"

    

    if [[ -f "${volume_file}" ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# volume - [Описание переменной]
# volume - [Variable description]
#
        volume=$(cat "${volume_file}")

    fi

    

    if [[ -f "${muted_file}" ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# muted - [Описание переменной]
# muted - [Variable description]
#
        muted=$(cat "${muted_file}")

    fi

    

    if [[ "${muted}" == "true" ]]; then

        echo -e "${PS1_STATUS_COLOR_AUDIO_OFF}♪M${PS1_STATUS_COLOR_RESET}"

    elif (( volume > 70 )); then

        echo -e "${PS1_STATUS_COLOR_AUDIO_ON}♪♪♪${PS1_STATUS_COLOR_RESET}"

    elif (( volume > 40 )); then

        echo -e "${PS1_STATUS_COLOR_AUDIO_ON}♪♪${PS1_STATUS_COLOR_RESET}"

    elif (( volume > 0 )); then

        echo -e "${PS1_STATUS_COLOR_AUDIO_ON}♪${PS1_STATUS_COLOR_RESET}"

    else

        echo -e "${PS1_STATUS_COLOR_AUDIO_OFF}♪0${PS1_STATUS_COLOR_RESET}"

    fi

}



# Toggle audio mute

ps1status::audio::toggle_mute() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::audio::toggle_mute"

    

    if command -v pactl >/dev/null 2>&1; then

        pactl set-sink-mute @DEFAULT_SINK@ toggle

    elif command -v amixer >/dev/null 2>&1; then

        amixer set Master toggle >/dev/null 2>&1 || amixer set PCM toggle >/dev/null 2>&1

    else

        log::warn "No audio control tools found"

    fi

}



# Adjust volume

ps1status::audio::adjust_volume() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::audio::adjust_volume"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# delta - локальная переменная для этой функции
# delta - local variable for this function
#
    local delta="${1:-5}"

    

    if command -v pactl >/dev/null 2>&1; then

        pactl set-sink-volume @DEFAULT_SINK@ "${delta}%+"

    elif command -v amixer >/dev/null 2>&1; then

        amixer set Master "${delta}%+" >/dev/null 2>&1 || amixer set PCM "${delta}%+" >/dev/null 2>&1

    else

        log::warn "No audio control tools found"

    fi

}



# ============================================================================

# SYSTEM STATUS COMPONENT

# Компонент статуса системы

# ============================================================================



ps1status::system::init() {

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SYSTEM_LAST_CPU - [Описание переменной]
# PS1_STATUS_SYSTEM_LAST_CPU - [Variable description]
#
    PS1_STATUS_SYSTEM_LAST_CPU="0"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SYSTEM_LAST_MEM - [Описание переменной]
# PS1_STATUS_SYSTEM_LAST_MEM - [Variable description]
#
    PS1_STATUS_SYSTEM_LAST_MEM="0"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SYSTEM_LAST_LOAD - [Описание переменной]
# PS1_STATUS_SYSTEM_LAST_LOAD - [Variable description]
#
    PS1_STATUS_SYSTEM_LAST_LOAD="0"

}



ps1status::system::update() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::system::update"

    

    # Get CPU usage

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# cpu_usage - локальная переменная для этой функции
# cpu_usage - local variable for this function
#
    local cpu_usage

    cpu_usage=$(ps -o %cpu= -A 2>/dev/null | awk '{s+=$1} END {print s}' | xargs || echo "0")

    

    # Get memory usage

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# mem_usage - локальная переменная для этой функции
# mem_usage - local variable for this function
#
    local mem_usage

    if command -v free >/dev/null 2>&1; then

        mem_usage=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}' 2>/dev/null || echo "0")

    else

#
# ПЕРЕМЕННАЯ / VARIABLE:
# mem_usage - [Описание переменной]
# mem_usage - [Variable description]
#
        mem_usage="0"

    fi

    

    # Get load average

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# load_avg - локальная переменная для этой функции
# load_avg - local variable for this function
#
    local load_avg

    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs || echo "0")

    

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SYSTEM_LAST_CPU - [Описание переменной]
# PS1_STATUS_SYSTEM_LAST_CPU - [Variable description]
#
    PS1_STATUS_SYSTEM_LAST_CPU="${cpu_usage}"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SYSTEM_LAST_MEM - [Описание переменной]
# PS1_STATUS_SYSTEM_LAST_MEM - [Variable description]
#
    PS1_STATUS_SYSTEM_LAST_MEM="${mem_usage}"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_SYSTEM_LAST_LOAD - [Описание переменной]
# PS1_STATUS_SYSTEM_LAST_LOAD - [Variable description]
#
    PS1_STATUS_SYSTEM_LAST_LOAD="${load_avg}"

    

    # Cache results

    echo "${cpu_usage}" > "${PS1_STATUS_CACHE_DIR}/system.cpu"

    echo "${mem_usage}" > "${PS1_STATUS_CACHE_DIR}/system.mem"

    echo "${load_avg}" > "${PS1_STATUS_CACHE_DIR}/system.load"

}



ps1status::system::get_status() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# cpu_file - локальная переменная для этой функции
# cpu_file - local variable for this function
#
    local cpu_file="${PS1_STATUS_CACHE_DIR}/system.cpu"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# mem_file - локальная переменная для этой функции
# mem_file - local variable for this function
#
    local mem_file="${PS1_STATUS_CACHE_DIR}/system.mem"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# load_file - локальная переменная для этой функции
# load_file - local variable for this function
#
    local load_file="${PS1_STATUS_CACHE_DIR}/system.load"

    

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# cpu - локальная переменная для этой функции
# cpu - local variable for this function
#
    local cpu="0"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# mem - локальная переменная для этой функции
# mem - local variable for this function
#
    local mem="0"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# load - локальная переменная для этой функции
# load - local variable for this function
#
    local load="0"

    

    if [[ -f "${cpu_file}" ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# cpu - [Описание переменной]
# cpu - [Variable description]
#
        cpu=$(cat "${cpu_file}")

    fi

    

    if [[ -f "${mem_file}" ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# mem - [Описание переменной]
# mem - [Variable description]
#
        mem=$(cat "${mem_file}")

    fi

    

    if [[ -f "${load_file}" ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# load - [Описание переменной]
# load - [Variable description]
#
        load=$(cat "${load_file}")

    fi

    

    # Format system status

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# cpu_indicator - локальная переменная для этой функции
# cpu_indicator - local variable for this function
#
    local cpu_indicator="▪"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# mem_indicator - локальная переменная для этой функции
# mem_indicator - local variable for this function
#
    local mem_indicator="▪"

    

    if (( $(echo "${cpu} > 80" | bc -l 2>/dev/null || echo "0") )); then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# cpu_indicator - [Описание переменной]
# cpu_indicator - [Variable description]
#
        cpu_indicator="${PS1_STATUS_COLOR_SPEED_SLOW}▪${PS1_STATUS_COLOR_RESET}"

    elif (( $(echo "${cpu} > 50" | bc -l 2>/dev/null || echo "0") )); then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# cpu_indicator - [Описание переменной]
# cpu_indicator - [Variable description]
#
        cpu_indicator="${PS1_STATUS_COLOR_SPEED_MEDIUM}▪${PS1_STATUS_COLOR_RESET}"

    else

#
# ПЕРЕМЕННАЯ / VARIABLE:
# cpu_indicator - [Описание переменной]
# cpu_indicator - [Variable description]
#
        cpu_indicator="${PS1_STATUS_COLOR_SPEED_GOOD}▪${PS1_STATUS_COLOR_RESET}"

    fi

    

    if (( $(echo "${mem} > 80" | bc -l 2>/dev/null || echo "0") )); then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# mem_indicator - [Описание переменной]
# mem_indicator - [Variable description]
#
        mem_indicator="${PS1_STATUS_COLOR_SPEED_SLOW}▪${PS1_STATUS_COLOR_RESET}"

    elif (( $(echo "${mem} > 50" | bc -l 2>/dev/null || echo "0") )); then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# mem_indicator - [Описание переменной]
# mem_indicator - [Variable description]
#
        mem_indicator="${PS1_STATUS_COLOR_SPEED_MEDIUM}▪${PS1_STATUS_COLOR_RESET}"

    else

#
# ПЕРЕМЕННАЯ / VARIABLE:
# mem_indicator - [Описание переменной]
# mem_indicator - [Variable description]
#
        mem_indicator="${PS1_STATUS_COLOR_SPEED_GOOD}▪${PS1_STATUS_COLOR_RESET}"

    fi

    

    echo -e "${cpu_indicator}${mem_indicator}"

}



# ============================================================================

# COMPONENT MANAGEMENT

# Управление компонентами

# ============================================================================



# Enable status component

ps1status::enable_component() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::enable_component"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# component - локальная переменная для этой функции
# component - local variable for this function
#
    local component="${1:-}"

    

    if [[ -z "${component}" ]]; then

        errorhandler::throw "${func_name}" "Component name is required" \

            "${LIB_ERROR_INVALID_ARGS}"

    fi

    

    # Check if component exists

    if ! command -v "ps1status::${component}::get_status" >/dev/null 2>&1; then

        errorhandler::throw "${func_name}" "Unknown component: ${component}" \

            "${LIB_ERROR_INVALID_ARGS}"

    fi

    

    # Add to enabled components if not already there

    if [[ ! " ${PS1_STATUS_ENABLED_COMPONENTS[@]} " =~ " ${component} " ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_ENABLED_COMPONENTS+ - [Описание переменной]
# PS1_STATUS_ENABLED_COMPONENTS+ - [Variable description]
#
        PS1_STATUS_ENABLED_COMPONENTS+=("${component}")

        log::info "Enabled PS1 status component: ${component}"

    else

        log::warn "Component ${component} is already enabled"

    fi

}



# Disable status component

ps1status::disable_component() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::disable_component"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# component - локальная переменная для этой функции
# component - local variable for this function
#
    local component="${1:-}"

    

    if [[ -z "${component}" ]]; then

        errorhandler::throw "${func_name}" "Component name is required" \

            "${LIB_ERROR_INVALID_ARGS}"

    fi

    

    # Remove from enabled components

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# new_components - локальная переменная для этой функции
# new_components - local variable for this function
#
    local new_components=()

    for enabled_component in "${PS1_STATUS_ENABLED_COMPONENTS[@]}"; do

        if [[ "${enabled_component}" != "${component}" ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# new_components+ - [Описание переменной]
# new_components+ - [Variable description]
#
            new_components+=("${enabled_component}")

        fi

    done

    

    if [[ ${#new_components[@]} -ne ${#PS1_STATUS_ENABLED_COMPONENTS[@]} ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1_STATUS_ENABLED_COMPONENTS - [Описание переменной]
# PS1_STATUS_ENABLED_COMPONENTS - [Variable description]
#
        PS1_STATUS_ENABLED_COMPONENTS=("${new_components[@]}")

        log::info "Disabled PS1 status component: ${component}"

    else

        log::warn "Component ${component} was not enabled"

    fi

}



# Get enabled components

ps1status::get_enabled_components() {

    echo "${PS1_STATUS_ENABLED_COMPONENTS[@]}"

}



# ============================================================================

# PS1 CONSTRUCTION

# Формирование PS1

# ============================================================================



# Build PS1 status line

ps1status::build_ps1() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::build_ps1"

    

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# status_line - локальная переменная для этой функции
# status_line - local variable for this function
#
    local status_line=""

    

    # Add all enabled components

    for component in "${PS1_STATUS_ENABLED_COMPONENTS[@]}"; do

        if command -v "ps1status::${component}::get_status" >/dev/null 2>&1; then

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# component_status - локальная переменная для этой функции
# component_status - local variable for this function
#
            local component_status

#
# ПЕРЕМЕННАЯ / VARIABLE:
# component_status - [Описание переменной]
# component_status - [Variable description]
#
            component_status=$("ps1status::${component}::get_status")

#
# ПЕРЕМЕННАЯ / VARIABLE:
# status_line - [Описание переменной]
# status_line - [Variable description]
#
            status_line="${status_line}${component_status} "

        fi

    done

    

    # Add standard PS1 components

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# user_host - локальная переменная для этой функции
# user_host - local variable for this function
#
    local user_host="\[\033[01;32m\]\u@\h\[\033[00m\]"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# working_dir - локальная переменная для этой функции
# working_dir - local variable for this function
#
    local working_dir="\[\033[01;34m\]\w\[\033[00m\]"

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# prompt_char - локальная переменная для этой функции
# prompt_char - local variable for this function
#
    local prompt_char="\[\033[01;31m\]\$\[\033[00m\]"

    

    # Construct final PS1

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PS1 - [Описание переменной]
# PS1 - [Variable description]
#
    PS1="${status_line}${user_host}:${working_dir} ${prompt_char} "

    

    export PS1

}



# Enable PS1 status (install in PROMPT_COMMAND)

ps1status::enable() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::enable"

    

    # Add to PROMPT_COMMAND if not already there

    if [[ ! "${PROMPT_COMMAND:-}" =~ ps1status::build_ps1 ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PROMPT_COMMAND - [Описание переменной]
# PROMPT_COMMAND - [Variable description]
#
        PROMPT_COMMAND="ps1status::build_ps1${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

        export PROMPT_COMMAND

        log::info "PS1 status monitoring enabled"

    else

        log::debug "PS1 status monitoring already enabled"

    fi

}



# Disable PS1 status

ps1status::disable() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::disable"

    

    # Remove from PROMPT_COMMAND

    if [[ "${PROMPT_COMMAND:-}" =~ ps1status::build_ps1 ]]; then

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PROMPT_COMMAND - [Описание переменной]
# PROMPT_COMMAND - [Variable description]
#
        PROMPT_COMMAND="${PROMPT_COMMAND//ps1status::build_ps1/}"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PROMPT_COMMAND - [Описание переменной]
# PROMPT_COMMAND - [Variable description]
#
        PROMPT_COMMAND="${PROMPT_COMMAND#; }"

#
# ПЕРЕМЕННАЯ / VARIABLE:
# PROMPT_COMMAND - [Описание переменной]
# PROMPT_COMMAND - [Variable description]
#
        PROMPT_COMMAND="${PROMPT_COMMAND%; }"

        export PROMPT_COMMAND

        log::info "PS1 status monitoring disabled"

    fi

}



# ============================================================================

# AUDIO EQUALIZER CONTROL (Bonus Feature)

# Управление эквалайзером звука (Дополнительная функция)

# ============================================================================



# Check if equalizer is available

ps1status::equalizer::is_available() {

    if command -v pulseeffects >/dev/null 2>&1 || \

       command -v pulseaudio-equalizer >/dev/null 2>&1 || \

       command -v alsaequal >/dev/null 2>&1; then

        return 0

    else

        return 1

    fi

}



# Get equalizer status

ps1status::equalizer::get_status() {

    if ps1status::equalizer::is_available; then

        # Simple check - in real implementation, this would check actual equalizer state

        if systemctl --user is-active --quiet pulseeffects 2>/dev/null || \

           pgrep -x "pulseeffects" >/dev/null 2>&1; then

            echo -e "${PS1_STATUS_COLOR_AUDIO_ON}EQ♪${PS1_STATUS_COLOR_RESET}"

        else

            echo -e "${PS1_STATUS_COLOR_AUDIO_OFF}EQ${PS1_STATUS_COLOR_RESET}"

        fi

    else

        echo -e "${PS1_STATUS_COLOR_AUDIO_OFF}EQ${PS1_STATUS_COLOR_RESET}"

    fi

}



# Toggle equalizer

ps1status::equalizer::toggle() {

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# func_name - локальная переменная для этой функции
# func_name - local variable for this function
#
    local func_name="ps1status::equalizer::toggle"

    

    if command -v pulseeffects >/dev/null 2>&1; then

        if pgrep -x "pulseeffects" >/dev/null 2>&1; then

            pkill pulseeffects

            log::info "PulseEffects equalizer disabled"

        else

            pulseeffects &

            log::info "PulseEffects equalizer enabled"

        fi

    else

        log::warn "No equalizer tools found"

    fi

}



# ============================================================================

# MODULE INFO

# Информация о модуле

# ============================================================================



ps1status::info() {

    cat << EOF

PS1 Status Module v1.0.0



Available Components:

  wireguard    - WireGuard VPN connection status

  network      - Network connectivity status

  speed        - Internet speed monitoring

  audio        - Audio volume and mute status

  system       - CPU and memory usage

  equalizer    - Audio equalizer status (bonus)



Available Functions:

  ps1status::init                    - Initialize module

  ps1status::enable                  - Enable PS1 status monitoring

  ps1status::disable                 - Disable PS1 status monitoring

  ps1status::enable_component <name> - Enable status component

  ps1status::disable_component <name> - Disable status component

  ps1status::get_enabled_components  - List enabled components

  ps1status::start_monitoring        - Start background monitoring

  ps1status::stop_monitoring         - Stop background monitoring

  

  Audio Controls:

  ps1status::audio::toggle_mute      - Toggle audio mute

  ps1status::audio::adjust_volume [delta] - Adjust volume

  ps1status::equalizer::toggle       - Toggle equalizer



Status Indicators:

  WireGuard: WG↑ (up), WG↓ (down), WG? (unknown)

  Network: NET✓ (good), NET~ (medium), NET! (slow), NET✗ (down)

  Speed: ↓X.XM (Mbps)

  Audio: ♪♪♪ (high), ♪♪ (medium), ♪ (low), ♪M (muted), ♪0 (zero)

  System: ●● (CPU/Memory indicators)



Configuration:

  Config directory: ${PS1_STATUS_CONFIG_DIR}

  Cache directory: ${PS1_STATUS_CACHE_DIR}

  Update interval: ${PS1_STATUS_UPDATE_INTERVAL}s



Usage:

  ps1status::init

  ps1status::enable_component "wireguard"

  ps1status::enable_component "network"

  ps1status::enable

EOF

}
