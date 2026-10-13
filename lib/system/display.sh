#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, local/declare flags / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, local/declare flags
# display.sh — Display server and desktop environment configuration for system setup
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_DISPLAY" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @description Configure display server
# @param $1 Display server type ("x11", "wayland")
# @example
#   system::display::server "x11"
system::display::server() {
    local server_type="${1:-x11}"
    
    case "${server_type}" in
        x11)
            # For systems with X11
            if utils::has Xorg; then
                log::info "X11 display server available"
                # Check if xorg.conf exists, if not, generate one
                if ! is::file "/etc/X11/xorg.conf"; then
                    if utils::has Xorg; then
                        # This would typically require root privileges and is better done
                        # manually
                        log::info "X11 configuration file can be generated with 'Xorg -configure'"
                    fi
                fi
            else
                log::warn "X11 not installed"
                return "${E_ERROR}"
            fi
            ;;
        wayland)
            # For systems with Wayland
            if utils::has weston || utils::has sway; then
                log::info "Wayland display server available"
            else
                log::warn "Wayland not installed"
                return "${E_ERROR}"
            fi
            ;;
        *)
            log::warn "Unknown display server type: ${server_type}"
            return "${E_ERROR}"
            ;;
    esac
    
    log::info "Display server configured: ${server_type}"
}

# @description Configure desktop environment
# @param $1 Desktop environment ("gnome", "kde", "xfce", "mate", "cinnamon", "lxde",
# "none")
# @example
#   system::display::desktop "gnome"
system::display::desktop() {
    local de="${1:-none}"
    
    case "${de}" in
        gnome)
            # Check if GNOME is installed
            if utils::has gnome-shell; then
                log::info "GNOME desktop environment available"
                # Set GNOME as default
                if utils::has systemctl; then
                    utils::quiet_err systemctl set-default graphical.target
                fi
            else
                log::warn "GNOME not installed"
                return "${E_ERROR}"
            fi
            ;;
        kde)
            # Check if KDE is installed
            if utils::has startkde; then
                log::info "KDE desktop environment available"
                # Set KDE as default
                if utils::has systemctl; then
                    utils::quiet_err systemctl set-default graphical.target
                fi
            else
                log::warn "KDE not installed"
                return "${E_ERROR}"
            fi
            ;;
        xfce)
            # Check if XFCE is installed
            if utils::has startxfce4; then
                log::info "XFCE desktop environment available"
                # Set XFCE as default
                if utils::has systemctl; then
                    utils::quiet_err systemctl set-default graphical.target
                fi
            else
                log::warn "XFCE not installed"
                return "${E_ERROR}"
            fi
            ;;
        mate)
            # Check if MATE is installed
            if utils::has mate-session; then
                log::info "MATE desktop environment available"
                # Set MATE as default
                if utils::has systemctl; then
                    utils::quiet_err systemctl set-default graphical.target
                fi
            else
                log::warn "MATE not installed"
                return "${E_ERROR}"
            fi
            ;;
        cinnamon)
            # Check if Cinnamon is installed
            if utils::has cinnamon-session; then
                log::info "Cinnamon desktop environment available"
                # Set Cinnamon as default
                if utils::has systemctl; then
                    utils::quiet_err systemctl set-default graphical.target
                fi
            else
                log::warn "Cinnamon not installed"
                return "${E_ERROR}"
            fi
            ;;
        lxde)
            # Check if LXDE is installed
            if utils::has startlxde; then
                log::info "LXDE desktop environment available"
                # Set LXDE as default
                if utils::has systemctl; then
                    utils::quiet_err systemctl set-default graphical.target
                fi
            else
                log::warn "LXDE not installed"
                return "${E_ERROR}"
            fi
            ;;
        none)
            log::info "No desktop environment configured"
            # Set to text mode
            if utils::has systemctl; then
                utils::quiet_err systemctl set-default multi-user.target
            fi
            ;;
        *)
            log::warn "Unknown desktop environment: ${de}"
            return "${E_ERROR}"
            ;;
    esac
    
    log::info "Desktop environment configured: ${de}"
}

# @description Configure display manager
# @param $1 Display manager ("gdm", "sddm", "lightdm", "lxdm", "none")
# @example
#   system::display::manager "gdm"
system::display::manager() {
    local dm="${1:-none}"
    
    # Validate FIRST: stopping display-manager ends the user's graphical session, so it
    # must not happen for an unknown or not installed manager
    # Сначала проверка: остановка display-manager завершает графический сеанс пользователя,
    # для неизвестного или не установленного менеджера этого делать нельзя
    case "${dm}" in
        gdm|sddm|lightdm|lxdm)
            if ! utils::has "${dm}"; then
                log::warn "${dm} not installed"
                return "${E_ERROR}"
            fi
            log::info "${dm} display manager available"
            ;;
        none) ;;
        *)
            log::warn "Unknown display manager: ${dm}"
            return "${E_ERROR}"
            ;;
    esac
    
    # Stop any existing display manager / Остановить существующий менеджер дисплея
    if utils::has systemctl; then
        utils::quiet_err systemctl stop display-manager
    fi
    
    if utils::has systemctl; then
        if [[ "${dm}" == "none" ]]; then
            log::info "No display manager configured"
            utils::quiet_err systemctl disable display-manager
            if ! utils::quiet_err systemctl set-default multi-user.target; then
                log::error "systemctl set-default multi-user.target failed"
                return "${E_ERROR}"
            fi
        else
            # -f replaces the display-manager.service alias of the previous manager;
            # without it enable fails when another manager is already enabled
            # -f заменяет алиас display-manager.service прежнего менеджера; без него
            # enable падает, если другой менеджер уже включён
            if ! utils::quiet_err systemctl enable -f "${dm}"; then
                log::error "systemctl enable ${dm} failed"
                return "${E_ERROR}"
            fi
            if ! utils::quiet_err systemctl set-default graphical.target; then
                log::error "systemctl set-default graphical.target failed"
                return "${E_ERROR}"
            fi
        fi
    fi
    
    log::info "Display manager configured: ${dm}"
}

# @description Configure display resolution
# @param $1 Resolution (e.g., "1920x1080", "1366x768")
# @param $2 Display output (e.g., "HDMI-1", "VGA-1", optional)
# @example
#   system::display::resolution "1920x1080" "HDMI-1"
system::display::resolution() {
    local resolution="${1:-}"
    local output="${2:-}"
    
    if is::empty "${resolution}"; then
        log::warn "Resolution not specified"
        return "${E_ERROR}"
    fi
    
    if ! utils::has xrandr; then
        log::warn "xrandr not available, cannot set resolution"
        return "${E_ERROR}"
    fi
    
    if is::empty "${output}"; then
        output="$(xrandr --query | grep " connected" | head -n 1 | awk '{print $1}')"
    fi
    
    if is::empty "${output}"; then
        log::error "No connected output found"
        return "${E_ERROR}"
    fi
    
    if ! utils::quiet_err xrandr --output "${output}" --mode "${resolution}"; then
        log::error "xrandr failed to set ${resolution} on ${output}"
        return "${E_ERROR}"
    fi
    log::info "Display resolution set to ${resolution}"
}

# @description Configure display refresh rate
# @param $1 Refresh rate (e.g., "60", "75")
# @param $2 Display output (optional)
# @example
#   system::display::refresh "60" "HDMI-1"
system::display::refresh() {
    local rate="${1:-}"
    local output="${2:-}"
    
    if is::empty "${rate}"; then
        log::warn "Refresh rate not specified"
        return "${E_ERROR}"
    fi
    
    if ! utils::has xrandr; then
        log::warn "xrandr not available, cannot set refresh rate"
        return "${E_ERROR}"
    fi
    
    if is::empty "${output}"; then
        output="$(xrandr --query | grep " connected" | head -n 1 | awk '{print $1}')"
    fi
    
    if is::empty "${output}"; then
        log::error "No connected output found"
        return "${E_ERROR}"
    fi
    
    if ! utils::quiet_err xrandr --output "${output}" --rate "${rate}"; then
        log::error "xrandr failed to set ${rate}Hz on ${output}"
        return "${E_ERROR}"
    fi
    log::info "Display refresh rate set to ${rate}Hz"
}

# @description List available display modes
# @example
#   system::display::list_modes
system::display::list_modes() {
    # For X11 systems
    if utils::has xrandr; then
        utils::quiet_err xrandr --query || :
    else
        log::warn "xrandr not available, cannot list display modes"
        return "${E_ERROR}"
    fi
}

# @description Configure multiple displays
# @param $1 Layout ("extend", "mirror", "primary")
# @param $2 Primary display (optional)
# @example
#   system::display::multi "extend" "HDMI-1"
system::display::multi() {
    local layout="${1:-extend}"
    local primary="${2:-}"
    
    if ! utils::has xrandr; then
        log::warn "xrandr not available, cannot configure multiple displays"
        return "${E_ERROR}"
    fi
    
    local -a outputs=()
    mapfile -t outputs < <(xrandr --query | awk '/ connected/ {print $1}')
    
    # The named primary must be a connected output; otherwise "primary" would switch
    # EVERY output off (nothing matches the exclusion) and leave a black screen
    # Названный основной вывод должен быть подключён; иначе "primary" выключил бы ВСЕ
    # выводы (исключение ничего не находит) и оставил чёрный экран
    if is::not_empty "${primary}"; then
        local found=0 o
        for o in "${outputs[@]}"; do
            [[ "${o}" == "${primary}" ]] && found=1
        done
        if (( found == 0 )); then
            log::error "Output not connected: ${primary}"
            return "${E_ERROR}"
        fi
    fi
    
    case "${layout}" in
        extend)
            if ! utils::quiet_err xrandr --auto; then
                log::error "xrandr --auto failed"
                return "${E_ERROR}"
            fi
            if is::not_empty "${primary}"; then
                utils::quiet_err xrandr --output "${primary}" --primary || return "${E_ERROR}"
            fi
            log::info "Displays extended"
            ;;
        mirror)
            if (( ${#outputs[@]} == 0 )); then
                log::error "No connected output found"
                return "${E_ERROR}"
            fi
            local master="${primary:-${outputs[0]}}" other
            for other in "${outputs[@]}"; do
                [[ "${other}" == "${master}" ]] && continue
                if ! utils::quiet_err xrandr --output "${other}" --auto --same-as "${master}"; then
                    log::error "xrandr failed to mirror ${other} to ${master}"
                    return "${E_ERROR}"
                fi
            done
            log::info "Display mirroring configured"
            ;;
        primary)
            if is::empty "${primary}"; then
                log::warn "Primary output name required"
                return "${E_ERROR}"
            fi
            utils::quiet_err xrandr --output "${primary}" --primary || return "${E_ERROR}"
            local output
            for output in "${outputs[@]}"; do
                [[ "${output}" == "${primary}" ]] && continue
                utils::quiet_err xrandr --output "${output}" --off || return "${E_ERROR}"
            done
            log::info "Primary display configured: ${primary}"
            ;;
        *)
            log::warn "Unknown layout: ${layout}"
            return "${E_ERROR}"
            ;;
    esac
}
