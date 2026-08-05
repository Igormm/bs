#!/usr/bin/env bs
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

# @depends core/const, core/logger, core/utils, core/errorhandler, lib/system/platformcheck

# Source Guard / Защита от повторной загрузки

source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"

bs::guard "STATUS_PS1" || return 0

# Зависимости / Dependencies

bs::source_relative "../../core/const.sh"

bs::source_relative "../../core/logger.sh"

bs::source_relative "../../core/utils.sh"

bs::source_relative "../../core/errorhandler.sh"

bs::source_relative "../system/platformcheck.sh"

# PS1 Status configuration

readonly PS1_STATUS_CONFIG_DIR="${HOME}/.config/ps1status"

readonly PS1_STATUS_CACHE_DIR="/tmp/ps1_status_cache"

readonly PS1_STATUS_UPDATE_INTERVAL=5  # seconds

# Status components state

PS1_STATUS_COMPONENTS=(

    "wireguard"

    "network"

    "speed"

    "audio"

    "system"

)

PS1_STATUS_ENABLED_COMPONENTS=(

    "wireguard"

    "network"

    "system"

)

# Color definitions for status indicators

readonly PS1_STATUS_COLOR_WIREGUARD_UP="\033[0;32m"    # Green

readonly PS1_STATUS_COLOR_WIREGUARD_DOWN="\033[0;31m"  # Red

readonly PS1_STATUS_COLOR_NETWORK_UP="\033[0;32m"      # Green

readonly PS1_STATUS_COLOR_NETWORK_DOWN="\033[0;31m"    # Red

readonly PS1_STATUS_COLOR_SPEED_GOOD="\033[0;32m"      # Green

readonly PS1_STATUS_COLOR_SPEED_MEDIUM="\033[0;33m"    # Yellow

readonly PS1_STATUS_COLOR_SPEED_SLOW="\033[0;31m"      # Red

readonly PS1_STATUS_COLOR_AUDIO_ON="\033[0;35m"        # Magenta

readonly PS1_STATUS_COLOR_AUDIO_OFF="\033[0;37m"       # Gray

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

    if ! utils::has ping; then

        missing_deps+=("iputils-ping")

    fi

    

    if ! utils::has curl; then

        missing_deps+=("curl")

    fi

    

    if ! utils::has wg; then

        log::debug "WireGuard tools not found - WireGuard status will be disabled"

    fi

    

    if ! utils::has pactl && ! utils::has amixer; then

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

    

    if platformcheck::is_debian || platformcheck::is_ubuntu; then

        apt-get update

        apt-get install -y curl iputils-ping

    elif platformcheck::is_alma || platformcheck::is_fedora; then

        dnf install -y curl iputils

    elif platformcheck::is_macos; then

        if ! utils::has brew; then

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

            utils::ignore "ps1status::${component}::update"

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

        monitor_pid=$(cat "${pid_file}")

        

        if utils::quiet_err kill "${monitor_pid}"; then

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

    PS1_STATUS_WIREGUARD_INTERFACES=()

    PS1_STATUS_WIREGUARD_LAST_STATUS="unknown"

    

    # Find active WireGuard interfaces

    if utils::has wg; then

        while IFS= read -r interface; do

            if [[ -n "${interface}" ]]; then

                PS1_STATUS_WIREGUARD_INTERFACES+=("${interface}")

            fi

        done < <(utils::quiet_err wg show interfaces)

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

            if utils::quiet wg show "${interface}"; then

                status="up"

                break

            fi

        done

    fi

    

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

    PS1_STATUS_NETWORK_TEST_HOSTS=(

        "8.8.8.8"      # Google DNS

        "1.1.1.1"      # Cloudflare DNS

        "208.67.222.222" # OpenDNS

    )

    PS1_STATUS_NETWORK_LAST_STATUS="unknown"

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

        if utils::quiet ping -c 1 -W 1 "${host}"; then

            status="up"

            ((successful_pings++))

            

            # Get latency

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# latency - локальная переменная для этой функции
# latency - local variable for this function
#
            local latency

            latency=$(utils::quiet_err ping -c 1 -W 1 "${host}" | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/' || echo "0")

            total_latency=$(echo "${total_latency} + ${latency}" | utils::quiet_err bc -l || echo "${total_latency}")

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

        avg_latency=$(echo "scale=1; ${total_latency} / ${successful_pings}" | utils::quiet_err bc -l || echo "0")

    fi

    

    PS1_STATUS_NETWORK_LAST_STATUS="${status}"

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

        status=$(cat "${status_file}")

    fi

    

    if [[ -f "${latency_file}" ]]; then

        latency=$(cat "${latency_file}")

    fi

    

    case "${status}" in

        up)

            if (( $(echo "${latency} < 50" | utils::quiet_err bc -l || echo "1") )); then

                echo -e "${PS1_STATUS_COLOR_NETWORK_UP}NET✓${PS1_STATUS_COLOR_RESET}"

            elif (( $(echo "${latency} < 100" | utils::quiet_err bc -l || echo "1") )); then

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

    PS1_STATUS_SPEED_TEST_URL="https://speed.cloudflare.com/__down?bytes=1048576"  # 1MB

    PS1_STATUS_SPEED_LAST_DOWNLOAD="0"

    PS1_STATUS_SPEED_LAST_UPLOAD="0"

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

    

    PS1_STATUS_SPEED_LAST_TEST="${current_time}"

    

    # Quick speed test (download only for performance)

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# start_time - локальная переменная для этой функции
# start_time - local variable for this function
#
    local start_time=$(date +%s.%N)

    

    if utils::quiet_err curl -s -o /dev/null --max-time 10 "${PS1_STATUS_SPEED_TEST_URL}"; then

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
        local duration=$(echo "${end_time} - ${start_time}" | utils::quiet_err bc -l || echo "1")

        

        # Calculate speed in Mbps

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# speed - локальная переменная для этой функции
# speed - local variable for this function
#
        local speed=$(echo "scale=1; 8 / ${duration}" | utils::quiet_err bc -l || echo "0")

        

        PS1_STATUS_SPEED_LAST_DOWNLOAD="${speed}"

    else

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

        speed=$(cat "${speed_file}")

    fi

    

    if (( $(echo "${speed} > 50" | utils::quiet_err bc -l || echo "0") )); then

        echo -e "${PS1_STATUS_COLOR_SPEED_GOOD}↓${speed}M${PS1_STATUS_COLOR_RESET}"

    elif (( $(echo "${speed} > 10" | utils::quiet_err bc -l || echo "0") )); then

        echo -e "${PS1_STATUS_COLOR_SPEED_MEDIUM}↓${speed}M${PS1_STATUS_COLOR_RESET}"

    elif (( $(echo "${speed} > 0" | utils::quiet_err bc -l || echo "0") )); then

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

    PS1_STATUS_AUDIO_LAST_STATUS="unknown"

    PS1_STATUS_AUDIO_LAST_VOLUME="0"

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

    if utils::has pactl; then

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# sink_info - локальная переменная для этой функции
# sink_info - local variable for this function
#
        local sink_info

        sink_info=$(utils::quiet_err pactl info | grep "Default Sink" | cut -d: -f2 | xargs)

        

        if [[ -n "${sink_info}" ]]; then

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# sink_volume - локальная переменная для этой функции
# sink_volume - local variable for this function
#
            local sink_volume

            sink_volume=$(utils::quiet_err pactl list sinks | grep -A 10 "${sink_info}" | grep "Volume:" | head -1)

            

            # Extract volume percentage

            if [[ -n "${sink_volume}" ]]; then

                volume=$(echo "${sink_volume}" | sed 's/.*\([0-9]*\)%.*/\1/' || echo "0")

            fi

            

            # Check if muted

            if utils::quiet_err pactl list sinks | grep -A 10 "${sink_info}" | grep -q "Mute: yes"; then

                muted="true"

            fi

        fi

    # Fallback to ALSA

    elif utils::has amixer; then

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# mixer_info - локальная переменная для этой функции
# mixer_info - local variable for this function
#
        local mixer_info

        mixer_info=$(utils::quiet_err amixer get Master || utils::quiet_err amixer get PCM)

        

        if [[ -n "${mixer_info}" ]]; then

            # Extract volume

            volume=$(echo "${mixer_info}" | grep -o "[0-9]*%" | head -1 | tr -d '%' || echo "0")

            

            # Check if muted

            if echo "${mixer_info}" | grep -q "\[off\]"; then

                muted="true"

            fi

        fi

    fi

    

    PS1_STATUS_AUDIO_LAST_VOLUME="${volume}"

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

        volume=$(cat "${volume_file}")

    fi

    

    if [[ -f "${muted_file}" ]]; then

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

    

    if utils::has pactl; then

        pactl set-sink-mute @DEFAULT_SINK@ toggle

    elif utils::has amixer; then

        utils::quiet amixer set Master toggle || utils::quiet amixer set PCM toggle

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

    

    if utils::has pactl; then

        pactl set-sink-volume @DEFAULT_SINK@ "${delta}%+"

    elif utils::has amixer; then

        utils::quiet amixer set Master "${delta}%+" || utils::quiet amixer set PCM "${delta}%+"

    else

        log::warn "No audio control tools found"

    fi

}

# ============================================================================

# SYSTEM STATUS COMPONENT

# Компонент статуса системы

# ============================================================================

ps1status::system::init() {

    PS1_STATUS_SYSTEM_LAST_CPU="0"

    PS1_STATUS_SYSTEM_LAST_MEM="0"

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

    cpu_usage=$(utils::quiet_err ps -o %cpu= -A | awk '{s+=$1} END {print s}' | xargs || echo "0")

    

    # Get memory usage

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# mem_usage - локальная переменная для этой функции
# mem_usage - local variable for this function
#
    local mem_usage

    if utils::has free; then

        mem_usage=$(free | grep Mem | utils::quiet_err awk '{printf("%.1f", $3/$2 * 100.0)}' || echo "0")

    else

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

    

    PS1_STATUS_SYSTEM_LAST_CPU="${cpu_usage}"

    PS1_STATUS_SYSTEM_LAST_MEM="${mem_usage}"

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

        cpu=$(cat "${cpu_file}")

    fi

    

    if [[ -f "${mem_file}" ]]; then

        mem=$(cat "${mem_file}")

    fi

    

    if [[ -f "${load_file}" ]]; then

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

    

    if (( $(echo "${cpu} > 80" | utils::quiet_err bc -l || echo "0") )); then

        cpu_indicator="${PS1_STATUS_COLOR_SPEED_SLOW}▪${PS1_STATUS_COLOR_RESET}"

    elif (( $(echo "${cpu} > 50" | utils::quiet_err bc -l || echo "0") )); then

        cpu_indicator="${PS1_STATUS_COLOR_SPEED_MEDIUM}▪${PS1_STATUS_COLOR_RESET}"

    else

        cpu_indicator="${PS1_STATUS_COLOR_SPEED_GOOD}▪${PS1_STATUS_COLOR_RESET}"

    fi

    

    if (( $(echo "${mem} > 80" | utils::quiet_err bc -l || echo "0") )); then

        mem_indicator="${PS1_STATUS_COLOR_SPEED_SLOW}▪${PS1_STATUS_COLOR_RESET}"

    elif (( $(echo "${mem} > 50" | utils::quiet_err bc -l || echo "0") )); then

        mem_indicator="${PS1_STATUS_COLOR_SPEED_MEDIUM}▪${PS1_STATUS_COLOR_RESET}"

    else

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

    if ! utils::has "ps1status::${component}::get_status"; then

        errorhandler::throw "${func_name}" "Unknown component: ${component}" \

            "${LIB_ERROR_INVALID_ARGS}"

    fi

    

    # Add to enabled components if not already there

    if [[ ! " ${PS1_STATUS_ENABLED_COMPONENTS[*]} " =~ " ${component} " ]]; then

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

            new_components+=("${enabled_component}")

        fi

    done

    

    if [[ ${#new_components[@]} -ne ${#PS1_STATUS_ENABLED_COMPONENTS[@]} ]]; then

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

        if utils::has "ps1status::${component}::get_status"; then

#
# ЛОКАЛЬНАЯ ПЕРЕМЕННАЯ / LOCAL VARIABLE:
# component_status - локальная переменная для этой функции
# component_status - local variable for this function
#
            local component_status

            component_status=$("ps1status::${component}::get_status")

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

        PROMPT_COMMAND="${PROMPT_COMMAND//ps1status::build_ps1/}"

        PROMPT_COMMAND="${PROMPT_COMMAND#; }"

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

    if utils::has pulseeffects || \

       utils::has pulseaudio-equalizer || \

       utils::has alsaequal; then

        return 0

    else

        return 1

    fi

}

# Get equalizer status

ps1status::equalizer::get_status() {

    if ps1status::equalizer::is_available; then

        # Simple check - in real implementation, this would check actual equalizer state

        if utils::quiet_err systemctl --user is-active --quiet pulseeffects || \

           utils::quiet pgrep -x "pulseeffects"; then

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

    

    if utils::has pulseeffects; then

        if utils::quiet pgrep -x "pulseeffects"; then

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
