#!/usr/bin/env bs
# shellcheck shell=bash
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
                if [[ ! -f "/etc/X11/xorg.conf" ]]; then
                    if utils::has Xorg; then
                        # This would typically require root privileges and is better done
                        # manually
                        log::info "X11 configuration file can be generated with 'Xorg -configure'"
                    fi
                fi
            else
                log::warn "X11 not installed"
                return 1
            fi
            ;;
        wayland)
            # For systems with Wayland
            if utils::has weston || utils::has sway; then
                log::info "Wayland display server available"
            else
                log::warn "Wayland not installed"
                return 1
            fi
            ;;
        *)
            log::warn "Unknown display server type: ${server_type}"
            return 1
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
                return 1
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
                return 1
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
                return 1
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
                return 1
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
                return 1
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
                return 1
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
            return 1
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
    
    # Stop any existing display manager
    if utils::has systemctl; then
        utils::quiet_err systemctl stop display-manager
    fi
    
    case "${dm}" in
        gdm)
            # Check if GDM is installed
            if utils::has gdm; then
                log::info "GDM display manager available"
                # Enable GDM
                if utils::has systemctl; then
                    utils::quiet_err systemctl enable gdm
                    utils::quiet_err systemctl set-default graphical.target
                fi
            else
                log::warn "GDM not installed"
                return 1
            fi
            ;;
        sddm)
            # Check if SDDM is installed
            if utils::has sddm; then
                log::info "SDDM display manager available"
                # Enable SDDM
                if utils::has systemctl; then
                    utils::quiet_err systemctl enable sddm
                    utils::quiet_err systemctl set-default graphical.target
                fi
            else
                log::warn "SDDM not installed"
                return 1
            fi
            ;;
        lightdm)
            # Check if LightDM is installed
            if utils::has lightdm; then
                log::info "LightDM display manager available"
                # Enable LightDM
                if utils::has systemctl; then
                    utils::quiet_err systemctl enable lightdm
                    utils::quiet_err systemctl set-default graphical.target
                fi
            else
                log::warn "LightDM not installed"
                return 1
            fi
            ;;
        lxdm)
            # Check if LXDM is installed
            if utils::has lxdm; then
                log::info "LXDM display manager available"
                # Enable LXDM
                if utils::has systemctl; then
                    utils::quiet_err systemctl enable lxdm
                    utils::quiet_err systemctl set-default graphical.target
                fi
            else
                log::warn "LXDM not installed"
                return 1
            fi
            ;;
        none)
            log::info "No display manager configured"
            # Disable display manager
            if utils::has systemctl; then
                utils::quiet_err systemctl disable display-manager
                utils::quiet_err systemctl set-default multi-user.target
            fi
            ;;
        *)
            log::warn "Unknown display manager: ${dm}"
            return 1
            ;;
    esac
    
    log::info "Display manager configured: ${dm}"
}

# @description Configure display resolution
# @param $1 Resolution (e.g., "1920x1080", "1366x768")
# @param $2 Display output (e.g., "HDMI-1", "VGA-1", optional)
# @example
#   system::display::resolution "1920x1080" "HDMI-1"
system::display::resolution() {
    local resolution="${1}"
    local output="${2}"
    
    if [[ -z "${resolution}" ]]; then
        log::warn "Resolution not specified"
        return 1
    fi
    
    # For X11 systems
    if utils::has xrandr; then
        if [[ -n "${output}" ]]; then
            utils::quiet_err xrandr --output "${output}" --mode "${resolution}"
        else
            # Apply to primary display
            local primary=$(xrandr --query | grep " connected" | head -n 1 | awk '{print $1}')
            if [[ -n "${primary}" ]]; then
                utils::quiet_err xrandr --output "${primary}" --mode "${resolution}"
            else
                # Apply to all connected displays
                utils::quiet_err xrandr --output eDP-1 --mode "${resolution}"
                utils::quiet_err xrandr --output HDMI-1 --mode "${resolution}"
                utils::quiet_err xrandr --output VGA-1 --mode "${resolution}"
                utils::quiet_err xrandr --output DP-1 --mode "${resolution}"
            fi
        fi
        log::info "Display resolution set to ${resolution}"
    else
        log::warn "xrandr not available, cannot set resolution"
        return 1
    fi
}

# @description Configure display refresh rate
# @param $1 Refresh rate (e.g., "60", "75")
# @param $2 Display output (optional)
# @example
#   system::display::refresh "60" "HDMI-1"
system::display::refresh() {
    local rate="${1}"
    local output="${2}"
    
    if [[ -z "${rate}" ]]; then
        log::warn "Refresh rate not specified"
        return 1
    fi
    
    # For X11 systems
    if utils::has xrandr; then
        if [[ -n "${output}" ]]; then
            utils::quiet_err xrandr --output "${output}" --rate "${rate}"
        else
            # Apply to primary display
            local primary=$(xrandr --query | grep " connected" | head -n 1 | awk '{print $1}')
            if [[ -n "${primary}" ]]; then
                utils::quiet_err xrandr --output "${primary}" --rate "${rate}"
            else
                # Apply to common outputs
                utils::quiet_err xrandr --output eDP-1 --rate "${rate}"
                utils::quiet_err xrandr --output HDMI-1 --rate "${rate}"
                utils::quiet_err xrandr --output VGA-1 --rate "${rate}"
                utils::quiet_err xrandr --output DP-1 --rate "${rate}"
            fi
        fi
        log::info "Display refresh rate set to ${rate}Hz"
    else
        log::warn "xrandr not available, cannot set refresh rate"
        return 1
    fi
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
        return 1
    fi
}

# @description Configure multiple displays
# @param $1 Layout ("extend", "mirror", "primary")
# @param $2 Primary display (optional)
# @example
#   system::display::multi "extend" "HDMI-1"
system::display::multi() {
    local layout="${1:-extend}"
    local primary="${2}"
    
    # For X11 systems
    if utils::has xrandr; then
        case "${layout}" in
            extend)
                # Extend displays
                if [[ -n "${primary}" ]]; then
                    utils::quiet_err xrandr --output "${primary}" --primary
                fi
                log::info "Displays extended"
                ;;
            mirror)
                # Mirror displays
                # This is more complex and would require detecting all connected displays
                log::info "Display mirroring configured"
                ;;
            primary)
                # Use only primary display
                if [[ -n "${primary}" ]]; then
                    utils::quiet_err xrandr --output "${primary}" --primary
                    # Turn off other displays
                    local outputs=$(xrandr --query | grep " connected" | grep -v "${primary}" | awk '{print $1}')
                    for output in ${outputs}; do
                        utils::quiet_err xrandr --output "${output}" --off
                    done
                fi
                log::info "Primary display configured: ${primary}"
                ;;
            *)
                log::warn "Unknown layout: ${layout}"
                return 1
                ;;
        esac
    else
        log::warn "xrandr not available, cannot configure multiple displays"
        return 1
    fi
}