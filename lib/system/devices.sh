#!/usr/bin/env bs
# shellcheck shell=bash
# devices.sh — Input/output devices configuration for system setup / Конфигурация
# устройств ввода/вывода для настройки системы
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_DEVICES" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @description Configure mouse settings / Настроить параметры мыши
# @param $1 Setting name ("acceleration", "sensitivity", "natural-scroll") / Имя параметра
# ("acceleration", "sensitivity", "natural-scroll")
# @param $2 Setting value / Значение параметра
# @example
#   system::devices::mouse "acceleration" "2.0"
system::devices::mouse() {
    local setting="${1}"
    local value="${2}"
    
    if [[ -z "${setting}" ]] || [[ -z "${value}" ]]; then
        log::warn "Mouse setting and value must be specified"
        return 1
    fi
    
    # For X11 systems / Для систем X11
    if utils::has xinput; then
        # Find mouse devices / Найти устройства мыши
        local mice=$(xinput list --name-only | grep -i mouse)
        
        case "${setting}" in
            acceleration)
                # Set mouse acceleration / Установить ускорение мыши
                for mouse in ${mice}; do
                    utils::quiet_err xinput set-prop "${mouse}" "libinput Accel Speed" "${value}" || :
                done
                log::info "Mouse acceleration set to ${value}"
                ;;
            sensitivity)
                # Set mouse sensitivity / Установить чувствительность мыши
                for mouse in ${mice}; do
                    utils::quiet_err xinput set-prop "${mouse}" "libinput Accel Speed" "${value}" || :
                done
                log::info "Mouse sensitivity set to ${value}"
                ;;
            natural-scroll)
                # Enable/disable natural scrolling / Включить/отключить естественную
                # прокрутку
                local scroll_value=0
                if [[ "${value}" == "true" ]] || [[ "${value}" == "1" ]]; then
                    scroll_value=1
                fi
                
                for mouse in ${mice}; do
                    utils::quiet_err xinput set-prop "${mouse}" "libinput Natural Scrolling Enabled" "${scroll_value}" || :
                done
                log::info "Mouse natural scrolling set to ${value}"
                ;;
            *)
                log::warn "Unknown mouse setting: ${setting}"
                return 1
                ;;
        esac
    else
        log::warn "xinput not available, cannot configure mouse"
        return 1
    fi
}

# @description Configure keyboard settings
# @param $1 Setting name ("repeat-rate", "repeat-delay", "layout")
# @param $2 Setting value
# @example
#   system::devices::keyboard "repeat-rate" "30"
system::devices::keyboard() {
    local setting="${1}"
    local value="${2}"
    
    if [[ -z "${setting}" ]] || [[ -z "${value}" ]]; then
        log::warn "Keyboard setting and value must be specified"
        return 1
    fi
    
    case "${setting}" in
        repeat-rate)
            # Set keyboard repeat rate
            if utils::has xset; then
                # Get current delay
                local delay=$(utils::quiet_err xset q | grep rate | awk '{print $4}')
                utils::quiet_err xset r rate "${delay}" "${value}" || :
                log::info "Keyboard repeat rate set to ${value}"
            else
                log::warn "xset not available, cannot set keyboard repeat rate"
                return 1
            fi
            ;;
        repeat-delay)
            # Set keyboard repeat delay
            if utils::has xset; then
                # Get current rate
                local rate=$(utils::quiet_err xset q | grep rate | awk '{print $5}')
                utils::quiet_err xset r rate "${value}" "${rate}" || true
                log::info "Keyboard repeat delay set to ${value}"
            else
                log::warn "xset not available, cannot set keyboard repeat delay"
                return 1
            fi
            ;;
        layout)
            # Set keyboard layout
            if utils::has setxkbmap; then
                utils::quiet_err setxkbmap "${value}" || true
                log::info "Keyboard layout set to ${value}"
            else
                log::warn "setxkbmap not available, cannot set keyboard layout"
                return 1
            fi
            ;;
        *)
            log::warn "Unknown keyboard setting: ${setting}"
            return 1
            ;;
    esac
}

# @description Configure touchpad settings
# @param $1 Setting name ("tap-to-click", "natural-scroll", "disable-while-typing")
# @param $2 Setting value ("true", "false")
# @example
#   system::devices::touchpad "tap-to-click" "true"
system::devices::touchpad() {
    local setting="${1}"
    local value="${2}"
    
    if [[ -z "${setting}" ]] || [[ -z "${value}" ]]; then
        log::warn "Touchpad setting and value must be specified"
        return 1
    fi
    
    # For X11 systems with libinput
    if utils::has xinput; then
        # Find touchpad devices
        local touchpads=$(xinput list --name-only | grep -i touchpad)
        
        local bool_value=0
        if [[ "${value}" == "true" ]] || [[ "${value}" == "1" ]]; then
            bool_value=1
        fi
        
        case "${setting}" in
            tap-to-click)
                # Enable/disable tap to click
                for touchpad in ${touchpads}; do
                    utils::quiet_err xinput set-prop "${touchpad}" "libinput Tapping Enabled" "${bool_value}" || true
                done
                log::info "Touchpad tap-to-click set to ${value}"
                ;;
            natural-scroll)
                # Enable/disable natural scrolling
                for touchpad in ${touchpads}; do
                    utils::quiet_err xinput set-prop "${touchpad}" "libinput Natural Scrolling Enabled" "${bool_value}" || true
                done
                log::info "Touchpad natural scrolling set to ${value}"
                ;;
            disable-while-typing)
                # Enable/disable disable-while-typing
                for touchpad in ${touchpads}; do
                    utils::quiet_err xinput set-prop "${touchpad}" "libinput Disable While Typing Enabled" "${bool_value}" || true
                done
                log::info "Touchpad disable-while-typing set to ${value}"
                ;;
            *)
                log::warn "Unknown touchpad setting: ${setting}"
                return 1
                ;;
        esac
    else
        log::warn "xinput not available, cannot configure touchpad"
        return 1
    fi
}

# @description List input devices
# @example
#   system::devices::list
system::devices::list() {
    # For X11 systems
    if utils::has xinput; then
        utils::quiet_err xinput list || true
    else
        # Fallback to lsinput if available
        if utils::has lsinput; then
            utils::quiet_err lsinput || true
        else
            # Fallback to /proc/bus/input/devices
            if [[ -f "/proc/bus/input/devices" ]]; then
                utils::quiet_err cat /proc/bus/input/devices || true
            else
                log::warn "No method available to list input devices"
                return 1
            fi
        fi
    fi
}

# @description Configure audio settings
# @param $1 Setting name ("volume", "mute", "output-device")
# @param $2 Setting value
# @example
#   system::devices::audio "volume" "75"
system::devices::audio() {
    local setting="${1}"
    local value="${2}"
    
    if [[ -z "${setting}" ]] || [[ -z "${value}" ]]; then
        log::warn "Audio setting and value must be specified"
        return 1
    fi
    
    # For systems with PulseAudio
    if utils::has pactl; then
        case "${setting}" in
            volume)
                # Set volume
                utils::quiet_err pactl set-sink-volume @DEFAULT_SINK@ "${value}%" || true
                log::info "Audio volume set to ${value}%"
                ;;
            mute)
                # Mute/unmute
                if [[ "${value}" == "true" ]] || [[ "${value}" == "1" ]]; then
                    utils::quiet_err pactl set-sink-mute @DEFAULT_SINK@ 1 || true
                    log::info "Audio muted"
                else
                    utils::quiet_err pactl set-sink-mute @DEFAULT_SINK@ 0 || true
                    log::info "Audio unmuted"
                fi
                ;;
            output-device)
                # Set output device
                utils::quiet_err pactl set-default-sink "${value}" || true
                log::info "Audio output device set to ${value}"
                ;;
            *)
                log::warn "Unknown audio setting: ${setting}"
                return 1
                ;;
        esac
    # For systems with ALSA
    elif utils::has amixer; then
        case "${setting}" in
            volume)
                # Set volume
                utils::quiet_err amixer set Master "${value}%" || true
                log::info "Audio volume set to ${value}%"
                ;;
            mute)
                # Mute/unmute
                if [[ "${value}" == "true" ]] || [[ "${value}" == "1" ]]; then
                    utils::quiet_err amixer set Master mute || true
                    log::info "Audio muted"
                else
                    utils::quiet_err amixer set Master unmute || true
                    log::info "Audio unmuted"
                fi
                ;;
            *)
                log::warn "Unknown audio setting: ${setting}"
                return 1
                ;;
        esac
    else
        log::warn "No audio control utility available"
        return 1
    fi
}

# @description Configure display output devices
# @param $1 Setting name ("brightness", "primary", "off")
# @param $2 Setting value
# @example
#   system::devices::display "brightness" "80"
system::devices::display() {
    local setting="${1}"
    local value="${2}"
    
    if [[ -z "${setting}" ]] || [[ -z "${value}" ]]; then
        log::warn "Display setting and value must be specified"
        return 1
    fi
    
    case "${setting}" in
        brightness)
            # Set display brightness
            # Try xrandr first
            if utils::has xrandr; then
                # Get primary output
                local primary=$(xrandr --query | grep " connected" | head -n 1 | awk '{print $1}')
                if [[ -n "${primary}" ]]; then
                    # xrandr uses values from 0.0 to 1.0
                    local brightness=$(echo "scale=2; ${value}/100" | utils::quiet_err bc || echo "0.${value}")
                    utils::quiet_err xrandr --output "${primary}" --brightness "${brightness}" || true
                    log::info "Display brightness set to ${value}%"
                fi
            # Try sysfs
            elif [[ -w "/sys/class/backlight/intel_backlight/brightness" ]]; then
                # Calculate value based on max_brightness
                local max_brightness=$(cat /sys/class/backlight/intel_backlight/max_brightness)
                local brightness=$(echo "${value} * ${max_brightness} / 100" | utils::quiet_err bc || echo $((value * max_brightness / 100)))
                utils::quiet_err echo "${brightness}" > /sys/class/backlight/intel_backlight/brightness || true
                log::info "Display brightness set to ${value}%"
            else
                log::warn "No method available to set display brightness"
                return 1
            fi
            ;;
        primary)
            # Set primary display
            if utils::has xrandr; then
                utils::quiet_err xrandr --output "${value}" --primary || true
                log::info "Primary display set to ${value}"
            else
                log::warn "xrandr not available, cannot set primary display"
                return 1
            fi
            ;;
        off)
            # Turn off display
            if utils::has xrandr; then
                utils::quiet_err xrandr --output "${value}" --off || true
                log::info "Display ${value} turned off"
            else
                log::warn "xrandr not available, cannot turn off display"
                return 1
            fi
            ;;
        *)
            log::warn "Unknown display setting: ${setting}"
            return 1
            ;;
    esac
}