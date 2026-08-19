#!/usr/bin/env bs
# shellcheck shell=bash
# system.sh — System configuration module for BS / Модуль системной конфигурации для BS
#
# This module provides functions to configure Linux system settings. / Этот модуль
# предоставляет функции для настройки Linux системы.
#
# Usage / Использование:
#   load "lib/system"
#   system::keyboard_layout "us"
#   system::set_timezone "Europe/Moscow"
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_SYSTEM" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @description Set keyboard layout / Установить раскладку клавиатуры
# @param $1 Keyboard layout code (e.g., "us", "ru") / Код раскладки клавиатуры (например,
# "us", "ru")
# @example
#   system::keyboard_layout "us"
system::keyboard_layout() {
    local layout="${1:-us}"
    
    # For systemd-based systems / Для систем на базе systemd
    if utils::has localectl; then
        utils::attempt localectl set-keymap "${layout}"
    fi
    
    # For X11 systems / Для систем X11
    if utils::has setxkbmap; then
        utils::attempt setxkbmap "${layout}"
    fi
    
    log::info "Keyboard layout set to ${layout}"
}

# @description Set system locale / Установить системную локаль
# @param $1 Locale (e.g., "en_US.UTF-8", "ru_RU.UTF-8") / Локаль (например, "en_US.UTF-8",
# "ru_RU.UTF-8")
# @example
#   system::localization "en_US.UTF-8"
system::localization() {
    local locale="${1:-en_US.UTF-8}"
    
    # For systemd-based systems / Для систем на базе systemd
    if utils::has localectl; then
        utils::attempt localectl set-locale "${locale}"
    fi
    
    log::info "System locale set to ${locale}"
}

# @description Set system timezone / Установить системный часовой пояс
# @param $1 Timezone (e.g., "Europe/Moscow", "America/New_York") / Часовой пояс (например,
# "Europe/Moscow", "America/New_York")
# @example
#   system::date_time "Europe/Moscow"
system::date_time() {
    local timezone="${1:-UTC}"
    
    # For systemd-based systems / Для систем на базе systemd
    if utils::has timedatectl; then
        utils::attempt timedatectl set-timezone "${timezone}"
    fi
    
    log::info "System timezone set to ${timezone}"
}

# @description Configure display server / Настроить сервер отображения
# @param $1 Display server type ("x11", "wayland") / Тип сервера отображения
# @example
#   system::display_server "x11"
system::display_server() {
    # Delegate to display module / Делегирование модулю display
    load "lib/system/display"
    system::display::server "$@"
}

# @description Configure desktop environment / Настроить окружение рабочего стола
# @param $1 Desktop environment ("gnome", "kde", "xfce", ...) / Окружение рабочего стола
# @example
#   system::desktop_environment "gnome"
system::desktop_environment() {
    # Delegate to display module / Делегирование модулю display
    load "lib/system/display"
    system::display::desktop "$@"
}

# @description Configure display manager / Настроить менеджер отображения
# @param $1 Display manager ("gdm", "sddm", "lightdm", ...) / Менеджер отображения
# @example
#   system::display_manager "gdm"
system::display_manager() {
    # Delegate to display module / Делегирование модулю display
    load "lib/system/display"
    system::display::manager "$@"
}

# @description Configure routing table / Настроить таблицу маршрутизации
# @param $1 Table name or number / Имя или номер таблицы
# @param $2 Action ("add", "delete", "show") / Действие
# @example
#   system::routing_table "100" "show"
system::routing_table() {
    # Delegate to routing module / Делегирование модулю routing
    load "lib/system/routing"
    system::routing::table "$@"
}

# @description Configure logging settings / Настроить параметры логирования
# @param $1 Log level (e.g., "info", "warn", "error") / Уровень логирования
# @example
#   system::logging "info"
system::logging() {
    # Delegate to logging module / Делегирование модулю logging
    load "lib/system/logging"
    system::logging::configure "$@"
}