#!/usr/bin/env bs
# automation.sh — Automation tasks module for BS / Модуль задач автоматизации для BS
#
# This module provides functions to handle automation tasks based on the provided
# checklist
# / Этот модуль предоставляет функции для выполнения задач автоматизации на основе
# предоставленного чек-листа
#
# Usage / Использование:
#   load "lib/automation"
#   automation::locale::check_locale
#   automation::locale::set_locale "ru_RU.UTF-8"
#   automation::locale::verify_locale "ru_RU.UTF-8"
# @depends core/const, core/logger, core/utils, lib/system/distro

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../core/guard.sh"
bs::guard "AUTOMATION" || return 0

# Зависимости / Dependencies
bs::source_relative "../core/const.sh" "../core/logger.sh" "../core/utils.sh" "system/distro.sh"

# @description Check current keyboard layout / Проверить текущую раскладку клавиатуры
# @example
#   automation::locale::check_keyboard_layout
automation::locale::check_keyboard_layout() {
    if utils::has setxkbmap; then
        log::info "Current keyboard layout: $(setxkbmap -query | grep layout | awk '{print $2}')"
    elif utils::has localectl; then
        log::info "Current keyboard layout: $(localectl status | grep "X11 Layout" | awk '{print $3}')"
    else
        log::warn "No keyboard layout tool available"
        return 1
    fi
}

# @description Set keyboard layout / Установить раскладку клавиатуры
# @param $1 Layout code (e.g., "us", "ru") / Код раскладки (например, "us", "ru")
# @example
#   automation::locale::set_keyboard_layout "us"
automation::locale::set_keyboard_layout() {
    local layout="${1:-us}"
    
    # For systemd-based systems / Для систем на базе systemd
    if utils::has localectl; then
        utils::quiet_err localectl set-keymap "${layout}" || true
    fi
    
    # For X11 systems / Для систем X11
    if utils::has setxkbmap; then
        utils::quiet_err setxkbmap "${layout}" || true
    fi
    
    log::info "Keyboard layout set to ${layout}"
}

# @description Verify applied keyboard layout / Проверить примененную раскладку
# @param $1 Expected layout code / Ожидаемый код раскладки
# @example
#   automation::locale::verify_keyboard_layout "us"
automation::locale::verify_keyboard_layout() {
    local expected_layout="${1:-us}"
    local current_layout
    
    if utils::has setxkbmap; then
        current_layout=$(setxkbmap -query | grep layout | awk '{print $2}')
    elif utils::has localectl; then
        current_layout=$(localectl status | grep "X11 Layout" | awk '{print $3}' | tr -d '()')
    else
        log::warn "No keyboard layout tool available"
        return 1
    fi
    
    if [[ "${current_layout}" == "${expected_layout}" ]]; then
        log::info "[OK] Keyboard layout is set to ${expected_layout}"
        return 0
    else
        log::error "[FAIL] Expected layout ${expected_layout}, but got ${current_layout}"
        return 1
    fi
}

# @description Check current system locale / Проверить текущую системную локаль
# @example
#   automation::locale::check_locale
automation::locale::check_locale() {
    log::info "Current locale: $LANG"
    if utils::has localectl; then
        localectl status | grep "System Locale"
    fi
}

# @description Set system locale / Установить системную локаль
# @param $1 Locale (e.g., "en_US.UTF-8", "ru_RU.UTF-8") / Локаль (например, "en_US.UTF-8",
# "ru_RU.UTF-8")
# @example
#   automation::locale::set_locale "ru_RU.UTF-8"
automation::locale::set_locale() {
    local target_locale="${1:-en_US.UTF-8}"
    
    # For Debian/Ubuntu systems / Для систем Debian/Ubuntu
    if [[ -f /etc/debian_version ]]; then
        # Check if locale exists in available locales
        if grep -q "^${target_locale}" /etc/locale.gen; then
            # Uncomment the locale if it's commented
            utils::quiet_err sed -i "s/# ${target_locale}/${target_locale}/" /etc/locale.gen || \
            sed -i "s/#${target_locale}/${target_locale}/" /etc/locale.gen
        else
            # Add the locale to the list if it doesn't exist
            echo "${target_locale} UTF-8" >> /etc/locale.gen
        fi
        
        locale-gen
        update-locale LANG="${target_locale}"
    # For Fedora/ALT systems / Для систем Fedora/ALT
    elif [[ -f /etc/fedora-release ]] || [[ -f /etc/altlinux-release ]]; then
        if utils::has localectl; then
            localectl set-locale LANG="${target_locale}"
        else
            log::warn "localectl not available, setting locale manually"
            echo "LANG=${target_locale}" > /etc/locale.conf
            export LANG="${target_locale}"
        fi
    else
        log::warn "Unsupported distribution for locale configuration"
        return 1
    fi
    
    log::info "Locale set to ${target_locale}"
}

# @description Verify locale generation and switching / Проверить генерацию и переключение
# локали
# @param $1 Expected locale / Ожидаемая локаль
# @example
#   automation::locale::verify_locale "ru_RU.UTF-8"
automation::locale::verify_locale() {
    local expected_locale="${1}"
    
    if [[ "$LANG" == *"${expected_locale}"* ]]; then
        log::info "[OK] Locale is set to ${expected_locale}"
        return 0
    else
        # Check in system locale file
        local system_locale=""
        if [[ -f /etc/default/locale ]]; then
            system_locale=$(grep "^LANG=" /etc/default/locale | cut -d= -f2 | tr -d '"')
        elif [[ -f /etc/locale.conf ]]; then
            system_locale=$(grep "^LANG=" /etc/locale.conf | cut -d= -f2 | tr -d '"')
        fi
        
        if [[ "${system_locale}" == *"${expected_locale}"* ]]; then
            log::info "[OK] Locale is set to ${expected_locale} (in system config)"
            return 0
        else
            log::error "[FAIL] Expected locale ${expected_locale}, but got LANG=$LANG"
            return 1
        fi
    fi
}

# @description Check current timezone / Проверить текущий часовой пояс
# @example
#   automation::locale::check_timezone
automation::locale::check_timezone() {
    if utils::has timedatectl; then
        timedatectl status | grep -E "(Time zone|Local time|Universal time)"
    else
        log::info "Current timezone: $(utils::quiet_err cat /etc/timezone || readlink /etc/localtime | cut -d/ -f5-6)"
    fi
}

# @description Set timezone and time synchronization / Установить часовой пояс и
# синхронизацию времени
# @param $1 Timezone (e.g., "Europe/Moscow", "America/New_York") / Часовой пояс
# @example
#   automation::locale::set_timezone "Europe/Moscow"
automation::locale::set_timezone() {
    local timezone="${1:-UTC}"
    
    if utils::has timedatectl; then
        timedatectl set-timezone "${timezone}"
        timedatectl set-ntp true
    else
        # Manual method for systems without timedatectl
        ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime
        if utils::has hwclock; then
            hwclock --systohc
        fi
    fi
    
    log::info "Timezone set to ${timezone} and NTP synchronization enabled"
}

# @description Verify time and timezone correctness / Проверить корректность времени и
# таймзоны
# @param $1 Expected timezone / Ожидаемый часовой пояс
# @example
#   automation::locale::verify_timezone "Europe/Moscow"
automation::locale::verify_timezone() {
    local expected_tz="${1}"
    local current_tz
    
    if utils::has timedatectl; then
        current_tz=$(timedatectl status | grep "Time zone" | awk '{print $3}')
    else
        current_tz=$(readlink /etc/localtime | rev | cut -d/ -f1-2 | rev)
    fi
    
    if [[ "${current_tz}" == "${expected_tz}" ]]; then
        log::info "[OK] Timezone is set to ${expected_tz}"
        return 0
    else
        log::error "[FAIL] Expected timezone ${expected_tz}, but got ${current_tz}"
        return 1
    fi
}

# @description Scan connected input devices / Сканировать подключенные устройства ввода
# @example
#   automation::hardware::scan_input_devices
automation::hardware::scan_input_devices() {
    if utils::has xinput; then
        log::info "Input devices via xinput:"
        xinput list
    elif utils::has lsinput; then
        log::info "Input devices via lsinput:"
        lsinput
    else
        log::info "Input devices via /dev/input:"
        ls -la /dev/input/
    fi
}

# @description Set input device settings (e.g., mouse speed) / Установить настройки
# устройства ввода (например, скорость мыши)
# @param $1 Device name / Имя устройства
# @param $2 Property to set / Устанавливаемое свойство
# @param $3 Value to set / Значение для установки
# @example
#   automation::hardware::set_input_device "pointer" "Accel Speed" "0.5"
automation::hardware::set_input_device() {
    local device_name="${1}"
    local property="${2}"
    local value="${3}"
    
    if utils::has xinput; then
        local device_id=$(xinput list | grep -i "${device_name}" | grep -oP 'id=\K\d+' | head -n 1)
        if [[ -n "${device_id}" ]]; then
            xinput set-prop "${device_id}" "${property}" "${value}"
            log::info "Set ${property} to ${value} for device ${device_name}"
        else
            log::warn "Device ${device_name} not found"
            return 1
        fi
    else
        log::warn "xinput not available"
        return 1
    fi
}

# @description Check input device status / Проверить состояние устройств ввода
# @param $1 Device name to check / Имя устройства для проверки
# @example
#   automation::hardware::check_input_device "pointer"
automation::hardware::check_input_device() {
    local device_name="${1}"
    
    if utils::has xinput; then
        if xinput list | grep -qi "${device_name}"; then
            log::info "[OK] Device ${device_name} is connected"
            return 0
        else
            log::warn "[FAIL] Device ${device_name} not found"
            return 1
        fi
    else
        log::warn "xinput not available"
        return 1
    fi
}

# @description Detect active monitors / Определить активные мониторы
# @example
#   automation::hardware::detect_monitors
automation::hardware::detect_monitors() {
    if utils::has xrandr; then
        log::info "Active monitors:"
        xrandr --query | grep " connected"
    else
        log::warn "xrandr not available"
        return 1
    fi
}

# @description Set display resolution and orientation / Установить разрешение и ориентацию
# экрана
# @param $1 Monitor name / Имя монитора
# @param $2 Resolution (e.g., "1920x1080") / Разрешение
# @param $3 Orientation (optional: normal, left, right, inverted) / Ориентация
# (опционально)
# @example
#   automation::hardware::set_display_mode "HDMI-1" "1920x1080" "normal"
automation::hardware::set_display_mode() {
    local monitor="${1}"
    local resolution="${2}"
    local orientation="${3:-normal}"
    
    if utils::has xrandr; then
        xrandr --output "${monitor}" --mode "${resolution}" --rotate "${orientation}"
        log::info "Set ${monitor} to ${resolution} with ${orientation} orientation"
    else
        log::warn "xrandr not available"
        return 1
    fi
}

# @description Check current display mode / Проверить текущий режим вывода
# @param $1 Monitor name to check / Имя монитора для проверки
# @example
#   automation::hardware::check_display_mode "HDMI-1"
automation::hardware::check_display_mode() {
    local monitor="${1}"
    
    if utils::has xrandr; then
        local mode_info=$(xrandr --query | grep -A 1 "${monitor}" | tail -n 1)
        if [[ -n "${mode_info}" ]]; then
            log::info "[OK] Monitor ${monitor} is in mode: ${mode_info}"
            return 0
        else
            log::warn "[FAIL] Monitor ${monitor} not found or not active"
            return 1
        fi
    else
        log::warn "xrandr not available"
        return 1
    fi
}

# @description List available network interfaces / Список доступных интерфейсов
# @example
#   automation::network::list_interfaces
automation::network::list_interfaces() {
    log::info "Network interfaces:"
    ip link show
}

# @description Bring up/down network interface and assign IP / Подъем/опускание интерфейса
# и назначение IP
# @param $1 Interface name / Имя интерфейса
# @param $2 Action (up/down) / Действие
# @param $3 IP address (optional) / IP-адрес (опционально)
# @example
#   automation::network::manage_interface "eth0" "up" "192.168.1.100/24"
automation::network::manage_interface() {
    local interface="${1}"
    local action="${2}"
    local ip_addr="${3:-}"
    
    case "${action}" in
        "up")
            ip link set "${interface}" up
            if [[ -n "${ip_addr}" ]]; then
                ip addr add "${ip_addr}" dev "${interface}"
            fi
            log::info "Interface ${interface} brought up"
            ;;
        "down")
            ip link set "${interface}" down
            log::info "Interface ${interface} brought down"
            ;;
        *)
            log::warn "Invalid action: ${action}. Use 'up' or 'down'."
            return 1
            ;;
    esac
}

# @description Check interface status and IP assignment / Проверка состояния интерфейса
# @param $1 Interface name / Имя интерфейса
# @example
#   automation::network::check_interface_status "eth0"
automation::network::check_interface_status() {
    local interface="${1}"
    
    local link_status=$(utils::quiet_err ip link show "${interface}" | grep -o "LOWER_UP\|DOWN" | head -n 1)
    local ip_status=$(utils::quiet_err ip addr show "${interface}" | grep "inet" | head -n 1)
    
    if [[ -n "${link_status}" ]] && [[ "${link_status}" == "LOWER_UP" ]]; then
        log::info "[OK] Interface ${interface} is UP"
        if [[ -n "${ip_status}" ]]; then
            log::info "IP assigned: ${ip_status}"
            return 0
        else
            log::warn "[WARNING] Interface ${interface} is UP but no IP assigned"
            return 0
        fi
    else
        log::error "[FAIL] Interface ${interface} is DOWN"
        return 1
    fi
}

# @description Show current routing table / Вывод текущей таблицы маршрутизации
# @example
#   automation::network::show_routing_table
automation::network::show_routing_table() {
    log::info "Current routing table:"
    ip route show
}

# @description Add/remove static routes / Добавление/удаление статических маршрутов
# @param $1 Action (add/del) / Действие
# @param $2 Destination network / Сеть назначения
# @param $3 Gateway / Шлюз
# @param $4 Interface (optional) / Интерфейс (опционально)
# @example
#   automation::network::manage_route "add" "192.168.2.0/24" "192.168.1.1" "eth0"
automation::network::manage_route() {
    local action="${1}"
    local dest_network="${2}"
    local gateway="${3}"
    local interface="${4:-}"
    
    if [[ -n "${interface}" ]]; then
        ip route "${action}" "${dest_network}" via "${gateway}" dev "${interface}"
    else
        ip route "${action}" "${dest_network}" via "${gateway}"
    fi
    
    log::info "Route ${action}ed: ${dest_network} via ${gateway} ${interface:+dev ${interface}}"
}

# @description Check gateway availability / Проверка доступности шлюза
# @param $1 Gateway IP / IP шлюза
# @example
#   automation::network::check_gateway "192.168.1.1"
automation::network::check_gateway() {
    local gateway="${1}"
    
    if utils::quiet ping -c 1 -W 5 "${gateway}"; then
        log::info "[OK] Gateway ${gateway} is reachable"
        return 0
    else
        log::error "[FAIL] Gateway ${gateway} is not reachable"
        return 1
    fi
}

# @description Check running display server / Проверить запущенный сервер отображения
# @example
#   automation::display::check_display_server
automation::display::check_display_server() {
    local display_server=""
    
    if [[ -n "${DISPLAY:-}" ]]; then
        display_server="X11 (DISPLAY=${DISPLAY})"
    elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        display_server="Wayland (WAYLAND_DISPLAY=${WAYLAND_DISPLAY})"
    else
        # Check for running processes
        if pgrep -x Xorg >/dev/null; then
            display_server="X11 (Xorg process running)"
        elif pgrep -x weston >/dev/null || pgrep -x gnome-shell-wayland >/dev/null; then
            display_server="Wayland (process running)"
        fi
    fi
    
    if [[ -n "${display_server}" ]]; then
        log::info "Display server: ${display_server}"
        return 0
    else
        log::info "No display server detected"
        return 1
    fi
}

# @description Install display server packages / Установить пакеты X11/Wayland
# @param $1 Display server type (x11 or wayland) / Тип сервера отображения
# @example
#   automation::display::install_display_server "x11"
automation::display::install_display_server() {
    local server_type="${1}"
    
    case "${server_type}" in
        "x11")
            if system::distro::is_family "debian"; then
                system::distro::install_package "xorg" "xserver-xorg-core"
            elif system::distro::is_family "redhat"; then
                system::distro::install_package "xorg-x11-server-Xorg" "xorg-x11-server-common"
            else
                log::warn "Unsupported distribution for X11 installation"
                return 1
            fi
            ;;
        "wayland")
            if system::distro::is_family "debian"; then
                system::distro::install_package "wayland" "weston"
            elif system::distro::is_family "redhat"; then
                system::distro::install_package "wayland" "weston"
            else
                log::warn "Unsupported distribution for Wayland installation"
                return 1
            fi
            ;;
        *)
            log::warn "Invalid server type: ${server_type}. Use 'x11' or 'wayland'."
            return 1
            ;;
    esac
    
    log::info "${server_type^} display server packages installed"
}

# @description Check display server socket availability / Проверить доступность сокета
# @example
#   automation::display::check_display_socket
automation::display::check_display_socket() {
    local socket_path=""
    
    if [[ -n "${DISPLAY:-}" ]]; then
        socket_path="/tmp/.X11-unix/X${DISPLAY#*:}"
        if [[ -S "${socket_path}" ]]; then
            log::info "[OK] X11 socket available: ${socket_path}"
            return 0
        else
            log::warn "[FAIL] X11 socket not available: ${socket_path}"
            return 1
        fi
    elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        socket_path="/run/user/$UID/${WAYLAND_DISPLAY}"
        if [[ -S "${socket_path}" ]]; then
            log::info "[OK] Wayland socket available: ${socket_path}"
            return 0
        else
            log::warn "[FAIL] Wayland socket not available: ${socket_path}"
            return 1
        fi
    else
        log::info "No active display server detected"
        return 1
    fi
}

# @description Detect installed desktop environment / Определить установленное окружение
# @example
#   automation::display::detect_desktop_environment
automation::display::detect_desktop_environment() {
    local de=""
    
    # Check for running processes
    if pgrep -x gnome-session >/dev/null; then
        de="GNOME"
    elif pgrep -x plasma_session >/dev/null; then
        de="KDE Plasma"
    elif pgrep -x mate-session >/dev/null; then
        de="MATE"
    elif pgrep -x xfce4-session >/dev/null; then
        de="XFCE"
    elif pgrep -x lxsession >/dev/null; then
        de="LXDE"
    elif pgrep -x lxqt-session >/dev/null; then
        de="LXQt"
    elif pgrep -x enlightenment_start >/dev/null; then
        de="Enlightenment"
    elif pgrep -x budgie-desktop >/dev/null; then
        de="Budgie"
    elif pgrep -x cinnamon-session >/dev/null; then
        de="Cinnamon"
    fi
    
    if [[ -n "${de}" ]]; then
        log::info "Detected Desktop Environment: ${de}"
        return 0
    else
        log::info "No desktop environment detected"
        return 1
    fi
}

# @description Install desktop environment / Установить DE
# @param $1 Desktop environment name / Имя окружения рабочего стола
# @example
#   automation::display::install_desktop_environment "gnome"
automation::display::install_desktop_environment() {
    local de="${1}"
    
    case "${de}" in
        "gnome")
            if system::distro::is_family "debian"; then
                system::distro::install_package "gnome" "gnome-shell"
            elif system::distro::is_family "redhat"; then
                system::distro::install_package "gnome-desktop3" "gnome-shell"
            else
                log::warn "Unsupported distribution for GNOME installation"
                return 1
            fi
            ;;
        "kde"|"plasma")
            if system::distro::is_family "debian"; then
                system::distro::install_package "kde-plasma-desktop" "plasma-workspace"
            elif system::distro::is_family "redhat"; then
                system::distro::install_package "kde-plasma-workspace" "plasma-desktop"
            else
                log::warn "Unsupported distribution for KDE installation"
                return 1
            fi
            ;;
        "xfce")
            if system::distro::is_family "debian"; then
                system::distro::install_package "xfce4" "xfce4-session"
            elif system::distro::is_family "redhat"; then
                system::distro::install_package "xfce4" "xfce4-session"
            else
                log::warn "Unsupported distribution for XFCE installation"
                return 1
            fi
            ;;
        "mate")
            if system::distro::is_family "debian"; then
                system::distro::install_package "mate-desktop-environment" "mate-session-manager"
            elif system::distro::is_family "redhat"; then
                system::distro::install_package "mate-desktop" "mate-session-manager"
            else
                log::warn "Unsupported distribution for MATE installation"
                return 1
            fi
            ;;
        *)
            log::warn "Unsupported desktop environment: ${de}"
            return 1
            ;;
    esac
    
    log::info "${de^} desktop environment installed"
}

# @description Check desktop environment processes / Проверить запуск процессов DE
# @param $1 Desktop environment name / Имя окружения рабочего стола
# @example
#   automation::display::check_desktop_environment "gnome"
automation::display::check_desktop_environment() {
    local de="${1}"
    local process=""
    
    case "${de}" in
        "gnome")
            process="gnome-session"
            ;;
        "kde"|"plasma")
            process="plasma_session\|kwin"
            ;;
        "xfce")
            process="xfce4-session"
            ;;
        "mate")
            process="mate-session"
            ;;
        *)
            log::warn "Unsupported desktop environment: ${de}"
            return 1
            ;;
    esac
    
    if pgrep -x "${process}" >/dev/null; then
        log::info "[OK] ${de^} desktop environment is running"
        return 0
    else
        log::warn "[FAIL] ${de^} desktop environment is not running"
        return 1
    fi
}

# @description Check active display manager / Проверить активный DM
# @example
#   automation::display::check_display_manager
automation::display::check_display_manager() {
    local active_dm=""
    
    # Check systemd services
    if systemctl is-active --quiet gdm; then
        active_dm="GDM (gdm)"
    elif systemctl is-active --quiet lightdm; then
        active_dm="LightDM (lightdm)"
    elif systemctl is-active --quiet sddm; then
        active_dm="SDDM (sddm)"
    elif systemctl is-active --quiet kdm; then
        active_dm="KDM (kdm)"
    elif systemctl is-active --quiet lxdm; then
        active_dm="LXDM (lxdm)"
    fi
    
    if [[ -n "${active_dm}" ]]; then
        log::info "Active Display Manager: ${active_dm}"
        return 0
    else
        log::info "No active display manager detected"
        return 1
    fi
}

# @description Install and enable default display manager / Установить и включить DM по
# умолчанию
# @param $1 Display manager name / Имя дисплейного менеджера
# @example
#   automation::display::install_display_manager "gdm"
automation::display::install_display_manager() {
    local dm="${1}"
    
    # Install the display manager
    if system::distro::is_family "debian"; then
        system::distro::install_package "${dm}"
    elif system::distro::is_family "redhat"; then
        system::distro::install_package "${dm}"
    else
        log::warn "Unsupported distribution for display manager installation"
        return 1
    fi
    
    # Enable the display manager
    systemctl enable "${dm}.service"
    systemctl start "${dm}.service"
    
    log::info "${dm} display manager installed and enabled"
}

# @description Check graphical login availability / Проверить возможность запуска
# графического входа
# @example
#   automation::display::check_graphical_login
automation::display::check_graphical_login() {
    local dm_service=""
    
    # Determine which DM is enabled
    if utils::quiet_err systemctl is-enabled --quiet gdm; then
        dm_service="gdm"
    elif utils::quiet_err systemctl is-enabled --quiet lightdm; then
        dm_service="lightdm"
    elif utils::quiet_err systemctl is-enabled --quiet sddm; then
        dm_service="sddm"
    elif utils::quiet_err systemctl is-enabled --quiet kdm; then
        dm_service="kdm"
    elif utils::quiet_err systemctl is-enabled --quiet lxdm; then
        dm_service="lxdm"
    fi
    
    if [[ -n "${dm_service}" ]]; then
        if systemctl is-active --quiet "${dm_service}"; then
            log::info "[OK] Graphical login is available via ${dm_service}"
            return 0
        else
            log::warn "[FAIL] ${dm_service} is enabled but not running"
            return 1
        fi
    else
        log::warn "[FAIL] No display manager is enabled"
        return 1
    fi
}

# @description Check service status / Проверить статус конкретного сервиса
# @param $1 Service name / Имя сервиса
# @example
#   automation::system::check_service_status "nginx"
automation::system::check_service_status() {
    local service_name="${1}"
    
    if systemctl is-active --quiet "${service_name}"; then
        log::info "${service_name} is active (running)"
        return 0
    else
        log::info "${service_name} is inactive (not running)"
        return 1
    fi
}

# @description Control service (start/stop/restart) / Запуск/остановка/перезагрузка
# сервиса
# @param $1 Service name / Имя сервиса
# @param $2 Action (start, stop, restart, reload) / Действие
# @example
#   automation::system::control_service "nginx" "restart"
automation::system::control_service() {
    local service_name="${1}"
    local action="${2}"
    
    case "${action}" in
        "start"|"stop"|"restart"|"reload"|"enable"|"disable")
            systemctl "${action}" "${service_name}"
            log::info "${action^}ed service: ${service_name}"
            ;;
        *)
            log::warn "Invalid action: ${action}. Use start, stop, restart, reload, enable, or disable."
            return 1
            ;;
    esac
}

# @description Check final service status (active/inactive) / Финальная проверка статуса
# @param $1 Service name / Имя сервиса
# @param $2 Expected status (active, inactive) / Ожидаемый статус
# @example
#   automation::system::verify_service_status "nginx" "active"
automation::system::verify_service_status() {
    local service_name="${1}"
    local expected_status="${2}"
    
    local current_status
    if systemctl is-active --quiet "${service_name}"; then
        current_status="active"
    else
        current_status="inactive"
    fi
    
    if [[ "${current_status}" == "${expected_status}" ]]; then
        log::info "[OK] Service ${service_name} is ${expected_status}"
        return 0
    else
        log::error "[FAIL] Service ${service_name} is ${current_status}, expected ${expected_status}"
        return 1
    fi
}

# @description Auto-detect system type (Debian/Ubuntu vs Fedora/ALT) / Автоопределение
# типа системы
# @example
#   automation::system::detect_package_manager
automation::system::detect_package_manager() {
    if utils::has apt; then
        log::info "Detected package manager: APT (Debian/Ubuntu based)"
        echo "apt"
    elif utils::has dnf; then
        log::info "Detected package manager: DNF (Fedora/RHEL based)"
        echo "dnf"
    elif utils::has yum; then
        log::info "Detected package manager: YUM (older RHEL based)"
        echo "yum"
    elif utils::has zypper; then
        log::info "Detected package manager: Zypper (openSUSE based)"
        echo "zypper"
    elif utils::has pacman; then
        log::info "Detected package manager: Pacman (Arch based)"
        echo "pacman"
    else
        log::warn "Could not detect package manager"
        return 1
    fi
}

# @description Update package cache / Функция обновления кэша пакетов
# @example
#   automation::system::update_package_cache
automation::system::update_package_cache() {
    case "$(utils::quiet_err automation::system::detect_package_manager)" in
        "apt")
            apt update
            ;;
        "dnf")
            dnf check-update
            ;;
        "yum")
            yum check-update
            ;;
        "zypper")
            zypper refresh
            ;;
        "pacman")
            pacman -Sy
            ;;
        *)
            log::warn "Unsupported package manager"
            return 1
            ;;
    esac
    
    log::info "Package cache updated"
}

# @description Install/remove packages / Функция установки/удаления пакетов
# @param $1 Action (install, remove) / Действие
# @param $@ Package names / Имена пакетов
# @example
#   automation::system::manage_packages "install" "curl" "wget"
automation::system::manage_packages() {
    local action="${1}"
    shift
    local packages=("$@")
    
    case "${action}" in
        "install")
            case "$(utils::quiet_err automation::system::detect_package_manager)" in
                "apt")
                    apt install -y "${packages[@]}"
                    ;;
                "dnf")
                    dnf install -y "${packages[@]}"
                    ;;
                "yum")
                    yum install -y "${packages[@]}"
                    ;;
                "zypper")
                    zypper install -y "${packages[@]}"
                    ;;
                "pacman")
                    pacman -S --noconfirm "${packages[@]}"
                    ;;
                *)
                    log::warn "Unsupported package manager"
                    return 1
                    ;;
            esac
            ;;
        "remove")
            case "$(utils::quiet_err automation::system::detect_package_manager)" in
                "apt")
                    apt remove -y "${packages[@]}"
                    ;;
                "dnf")
                    dnf remove -y "${packages[@]}"
                    ;;
                "yum")
                    yum remove -y "${packages[@]}"
                    ;;
                "zypper")
                    zypper remove -y "${packages[@]}"
                    ;;
                "pacman")
                    pacman -R --noconfirm "${packages[@]}"
                    ;;
                *)
                    log::warn "Unsupported package manager"
                    return 1
                    ;;
            esac
            ;;
        *)
            log::warn "Invalid action: ${action}. Use install or remove."
            return 1
            ;;
    esac
    
    log::info "${action^}ed packages: ${packages[*]}"
}

# @description Check installed package version / Проверка установленной версии пакета
# @param $1 Package name / Имя пакета
# @example
#   automation::system::check_package_version "curl"
automation::system::check_package_version() {
    local package="${1}"
    
    case "$(utils::quiet_err automation::system::detect_package_manager)" in
        "apt")
            utils::quiet_err dpkg -l "${package}" | grep "^ii" | awk '{print $2 ": " $3}'
            ;;
        "dnf"|"yum")
            utils::quiet_err rpm -q "${package}" || echo "${package} not installed"
            ;;
        "zypper")
            utils::quiet_err rpm -q "${package}" || echo "${package} not installed"
            ;;
        "pacman")
            utils::quiet_err pacman -Q "${package}" || echo "${package} not installed"
            ;;
        *)
            log::warn "Unsupported package manager"
            return 1
            ;;
    esac
}

# @description List connected repositories / Вывод списка подключенных репозиториев
# @example
#   automation::system::list_repositories
automation::system::list_repositories() {
    case "$(utils::quiet_err automation::system::detect_package_manager)" in
        "apt")
            cat /etc/apt/sources.list
            utils::quiet_err ls /etc/apt/sources.list.d/ | xargs -I {} echo "/etc/apt/sources.list.d/{}"
            ;;
        "dnf"|"yum")
            ls /etc/yum.repos.d/ | xargs -I {} echo "/etc/yum.repos.d/{}"
            ;;
        "zypper")
            zypper repos
            ;;
        "pacman")
            grep -v "^#" /etc/pacman.conf
            ;;
        *)
            log::warn "Unsupported package manager"
            return 1
            ;;
    esac
}

# @description Add new repository / Добавление нового репозитория
# @param $1 Repository URL or PPA / URL репозитория или PPA
# @example
#   automation::system::add_repository "ppa:nginx/stable"
automation::system::add_repository() {
    local repo="${1}"
    
    case "$(utils::quiet_err automation::system::detect_package_manager)" in
        "apt")
            add-apt-repository "${repo}" -y
            ;;
        "dnf")
            dnf config-manager --add-repo "${repo}"
            ;;
        *)
            log::warn "Adding repositories is not supported for this package manager"
            return 1
            ;;
    esac
    
    log::info "Added repository: ${repo}"
}

# @description Check repository validity / Проверка валидности репозитория
# @example
#   automation::system::check_repository_validity
automation::system::check_repository_validity() {
    case "$(utils::quiet_err automation::system::detect_package_manager)" in
        "apt")
            apt update --dry-run
            ;;
        "dnf")
            dnf check-update
            ;;
        *)
            log::warn "Repository validity check not supported for this package manager"
            return 1
            ;;
    esac
    
    log::info "Repository validity checked"
}

# @description Check firewall status / Проверить статус брандмауэра
# @example
#   automation::security::check_firewall_status
automation::security::check_firewall_status() {
    local fw_status=""
    
    if utils::has ufw && utils::quiet ufw status; then
        fw_status="UFW: $(ufw status | head -n 1)"
    elif utils::has firewall-cmd && systemctl is-active --quiet firewalld; then
        fw_status="Firewalld: $(utils::quiet_err firewall-cmd --state || echo 'inactive')"
    elif utils::has iptables; then
        fw_status="IPTables: $(iptables -L | head -n 1)"
    fi
    
    if [[ -n "${fw_status}" ]]; then
        log::info "Firewall status: ${fw_status}"
        return 0
    else
        log::info "No active firewall detected"
        return 1
    fi
}

# @description Configure basic firewall rules / Включение/настройка базовых правил
# @param $1 Action (enable, disable, allow, deny) / Действие
# @param $2 Rule parameters / Параметры правила
# @example
#   automation::security::configure_firewall "allow" "80/tcp"
automation::security::configure_firewall() {
    local action="${1}"
    local rule="${2}"
    
    if utils::has ufw; then
        case "${action}" in
            "allow")
                ufw allow "${rule}"
                ;;
            "deny")
                ufw deny "${rule}"
                ;;
            "enable")
                ufw enable
                ;;
            "disable")
                ufw disable
                ;;
            *)
                log::warn "Invalid UFW action: ${action}"
                return 1
                ;;
        esac
    elif utils::has firewall-cmd; then
        case "${action}" in
            "allow")
                firewall-cmd --permanent --add-port="${rule}"
                firewall-cmd --reload
                ;;
            "enable")
                systemctl enable firewalld
                systemctl start firewalld
                ;;
            "disable")
                systemctl disable firewalld
                systemctl stop firewalld
                ;;
            *)
                log::warn "Invalid Firewalld action: ${action}"
                return 1
                ;;
        esac
    else
        log::warn "No supported firewall command available"
        return 1
    fi
    
    log::info "Firewall ${action}: ${rule}"
}

# @description Check sudo availability for user / Проверка наличия sudo у пользователя
# @param $1 Username (optional, defaults to current user) / Имя пользователя (опционально)
# @example
#   automation::security::check_sudo_access
automation::security::check_sudo_access() {
    local username="${1:-$USER}"
    
    if utils::quiet_err sudo -l -U "${username}" | grep -q "(ALL : ALL)"; then
        log::info "[OK] User ${username} has sudo access"
        return 0
    else
        log::warn "[FAIL] User ${username} does not have sudo access"
        return 1
    fi
}

# @description Check logging service / Проверить службу логирования
# @example
#   automation::security::check_logging_service
automation::security::check_logging_service() {
    local log_service=""
    
    if systemctl is-active --quiet rsyslog; then
        log_service="rsyslog"
    elif systemctl is-active --quiet systemd-journald; then
        log_service="journald"
    elif systemctl is-active --quiet syslog-ng; then
        log_service="syslog-ng"
    fi
    
    if [[ -n "${log_service}" ]]; then
        log::info "Active logging service: ${log_service}"
        return 0
    else
        log::info "No active logging service detected"
        return 1
    fi
}

# @description Configure log rotation / Настройка ротации логов
# @param $1 Log file path / Путь к файлу лога
# @example
#   automation::security::configure_log_rotation "/var/log/myapp.log"
automation::security::configure_log_rotation() {
    local log_file="${1}"
    local log_dir=$(dirname "${log_file}")
    local base_name=$(basename "${log_file}")
    
    # Create a basic logrotate configuration
    local config_file="/etc/logrotate.d/${base_name}"
    cat > "${config_file}" << EOF
${log_file} {
    daily
    missingok
    rotate 10
    compress
    delaycompress
    notifempty
    create 640 $(utils::quiet_err stat -c "%U" "${log_file}" || echo "root") $(utils::quiet_err stat -c "%G" "${log_file}" || echo "adm")
    postrotate
        systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
    
    log::info "Log rotation configured for ${log_file} in ${config_file}"
}

# @description Test log writing / Проверка записи в логи
# @param $1 Test message / Тестовое сообщение
# @param $2 Log file path (optional) / Путь к файлу лога (опционально)
# @example
#   automation::security::test_log_writing "Test message" "/var/log/test.log"
automation::security::test_log_writing() {
    local message="${1}"
    local log_file="${2:-/tmp/test.log}"
    
    # Create the log file if it doesn't exist
    utils::quiet_err touch "${log_file}" || {
        log::warn "Cannot write to ${log_file}"
        return 1
    }
    
    # Write test message with timestamp
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${message}" >> "${log_file}"
    
    log::info "Test message written to ${log_file}"
}