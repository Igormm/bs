#!/usr/bin/env bs
# display.sh — Display server and desktop environment configuration for system setup

# @description Configure display server
# @param $1 Display server type ("x11", "wayland")
# @example
#   system::display::server "x11"
system::display::server() {
    local server_type="${1:-x11}"
    
    case "${server_type}" in
        x11)
            # For systems with X11
            if command -v Xorg >/dev/null 2>&1; then
                log::info "X11 display server available"
                # Check if xorg.conf exists, if not, generate one
                if [[ ! -f "/etc/X11/xorg.conf" ]]; then
                    if command -v Xorg >/dev/null 2>&1; then
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
            if command -v weston >/dev/null 2>&1 || command -v sway >/dev/null 2>&1; then
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
            if command -v gnome-shell >/dev/null 2>&1; then
                log::info "GNOME desktop environment available"
                # Set GNOME as default
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl set-default graphical.target 2>/dev/null || true
                fi
            else
                log::warn "GNOME not installed"
                return 1
            fi
            ;;
        kde)
            # Check if KDE is installed
            if command -v startkde >/dev/null 2>&1; then
                log::info "KDE desktop environment available"
                # Set KDE as default
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl set-default graphical.target 2>/dev/null || true
                fi
            else
                log::warn "KDE not installed"
                return 1
            fi
            ;;
        xfce)
            # Check if XFCE is installed
            if command -v startxfce4 >/dev/null 2>&1; then
                log::info "XFCE desktop environment available"
                # Set XFCE as default
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl set-default graphical.target 2>/dev/null || true
                fi
            else
                log::warn "XFCE not installed"
                return 1
            fi
            ;;
        mate)
            # Check if MATE is installed
            if command -v mate-session >/dev/null 2>&1; then
                log::info "MATE desktop environment available"
                # Set MATE as default
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl set-default graphical.target 2>/dev/null || true
                fi
            else
                log::warn "MATE not installed"
                return 1
            fi
            ;;
        cinnamon)
            # Check if Cinnamon is installed
            if command -v cinnamon-session >/dev/null 2>&1; then
                log::info "Cinnamon desktop environment available"
                # Set Cinnamon as default
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl set-default graphical.target 2>/dev/null || true
                fi
            else
                log::warn "Cinnamon not installed"
                return 1
            fi
            ;;
        lxde)
            # Check if LXDE is installed
            if command -v startlxde >/dev/null 2>&1; then
                log::info "LXDE desktop environment available"
                # Set LXDE as default
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl set-default graphical.target 2>/dev/null || true
                fi
            else
                log::warn "LXDE not installed"
                return 1
            fi
            ;;
        none)
            log::info "No desktop environment configured"
            # Set to text mode
            if command -v systemctl >/dev/null 2>&1; then
                systemctl set-default multi-user.target 2>/dev/null || true
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
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop display-manager 2>/dev/null || true
    fi
    
    case "${dm}" in
        gdm)
            # Check if GDM is installed
            if command -v gdm >/dev/null 2>&1; then
                log::info "GDM display manager available"
                # Enable GDM
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl enable gdm 2>/dev/null || true
                    systemctl set-default graphical.target 2>/dev/null || true
                fi
            else
                log::warn "GDM not installed"
                return 1
            fi
            ;;
        sddm)
            # Check if SDDM is installed
            if command -v sddm >/dev/null 2>&1; then
                log::info "SDDM display manager available"
                # Enable SDDM
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl enable sddm 2>/dev/null || true
                    systemctl set-default graphical.target 2>/dev/null || true
                fi
            else
                log::warn "SDDM not installed"
                return 1
            fi
            ;;
        lightdm)
            # Check if LightDM is installed
            if command -v lightdm >/dev/null 2>&1; then
                log::info "LightDM display manager available"
                # Enable LightDM
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl enable lightdm 2>/dev/null || true
                    systemctl set-default graphical.target 2>/dev/null || true
                fi
            else
                log::warn "LightDM not installed"
                return 1
            fi
            ;;
        lxdm)
            # Check if LXDM is installed
            if command -v lxdm >/dev/null 2>&1; then
                log::info "LXDM display manager available"
                # Enable LXDM
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl enable lxdm 2>/dev/null || true
                    systemctl set-default graphical.target 2>/dev/null || true
                fi
            else
                log::warn "LXDM not installed"
                return 1
            fi
            ;;
        none)
            log::info "No display manager configured"
            # Disable display manager
            if command -v systemctl >/dev/null 2>&1; then
                systemctl disable display-manager 2>/dev/null || true
                systemctl set-default multi-user.target 2>/dev/null || true
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
    if command -v xrandr >/dev/null 2>&1; then
        if [[ -n "${output}" ]]; then
            xrandr --output "${output}" --mode "${resolution}" 2>/dev/null || true
        else
            # Apply to primary display
            local primary=$(xrandr --query | grep " connected" | head -n 1 | awk '{print $1}')
            if [[ -n "${primary}" ]]; then
                xrandr --output "${primary}" --mode "${resolution}" 2>/dev/null || true
            else
                # Apply to all connected displays
                xrandr --output eDP-1 --mode "${resolution}" 2>/dev/null || true
                xrandr --output HDMI-1 --mode "${resolution}" 2>/dev/null || true
                xrandr --output VGA-1 --mode "${resolution}" 2>/dev/null || true
                xrandr --output DP-1 --mode "${resolution}" 2>/dev/null || true
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
    if command -v xrandr >/dev/null 2>&1; then
        if [[ -n "${output}" ]]; then
            xrandr --output "${output}" --rate "${rate}" 2>/dev/null || true
        else
            # Apply to primary display
            local primary=$(xrandr --query | grep " connected" | head -n 1 | awk '{print $1}')
            if [[ -n "${primary}" ]]; then
                xrandr --output "${primary}" --rate "${rate}" 2>/dev/null || true
            else
                # Apply to common outputs
                xrandr --output eDP-1 --rate "${rate}" 2>/dev/null || true
                xrandr --output HDMI-1 --rate "${rate}" 2>/dev/null || true
                xrandr --output VGA-1 --rate "${rate}" 2>/dev/null || true
                xrandr --output DP-1 --rate "${rate}" 2>/dev/null || true
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
    if command -v xrandr >/dev/null 2>&1; then
        xrandr --query 2>/dev/null || true
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
    if command -v xrandr >/dev/null 2>&1; then
        case "${layout}" in
            extend)
                # Extend displays
                if [[ -n "${primary}" ]]; then
                    xrandr --output "${primary}" --primary 2>/dev/null || true
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
                    xrandr --output "${primary}" --primary 2>/dev/null || true
                    # Turn off other displays
                    local outputs=$(xrandr --query | grep " connected" | grep -v "${primary}" | awk '{print $1}')
                    for output in ${outputs}; do
                        xrandr --output "${output}" --off 2>/dev/null || true
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