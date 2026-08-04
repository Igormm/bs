#!/usr/bin/env bs
# keyboard.sh — Keyboard layout configuration for system setup / Конфигурация раскладки
# клавиатуры для настройки системы
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "SYSTEM_KEYBOARD" || return 0

# Зависимости / Dependencies
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/const.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/logger.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/utils.sh"

# @description Set keyboard layout for console and X11 / Установить раскладку клавиатуры
# для консоли и X11
# @param $1 Keyboard layout code (e.g., "us", "ru") / Код раскладки клавиатуры (например,
# "us", "ru")
# @example
#   system::keyboard::layout "us"
system::keyboard::layout() {
    local layout="${1:-us}"
    
    # For systemd-based systems with localectl / Для систем на базе systemd с localectl
    if utils::has localectl; then
        utils::quiet_err localectl set-keymap "${layout}" || true
        # For X11 sessions / Для сессий X11
        utils::quiet_err localectl set-x11-keymap "${layout}" || true
    else
        # Fallback for non-systemd systems / Резервный вариант для систем без systemd
        if utils::has loadkeys; then
            utils::quiet_err loadkeys "${layout}" || true
        fi
        
        # For X11 systems / Для систем X11
        if utils::has setxkbmap; then
            utils::quiet_err setxkbmap "${layout}" || true
        fi
    fi
    
    log::info "Keyboard layout set to ${layout}"
}

# @description Set keyboard model / Установить модель клавиатуры
# @param $1 Keyboard model (e.g., "pc105", "pc104") / Модель клавиатуры (например,
# "pc105", "pc104")
# @example
#   system::keyboard::model "pc105"
system::keyboard::model() {
    local model="${1:-pc105}"
    
    if utils::has localectl; then
        utils::quiet_err localectl set-keymap --keymap-model "${model}" || true
    fi
    
    log::info "Keyboard model set to ${model}"
}

# @description Set keyboard variant / Установить вариант клавиатуры
# @param $1 Keyboard variant (e.g., "dvorak", "colemak") / Вариант клавиатуры (например,
# "dvorak", "colemak")
# @example
#   system::keyboard::variant "dvorak"
system::keyboard::variant() {
    local variant="${1}"
    
    if utils::has localectl; then
        utils::quiet_err localectl set-keymap --keymap-variant "${variant}" || true
    fi
    
    log::info "Keyboard variant set to ${variant}"
}

# @description Set keyboard options / Установить опции клавиатуры
# @param $1 Keyboard options (e.g., "ctrl:swapcaps") / Опции клавиатуры (например,
# "ctrl:swapcaps")
# @example
#   system::keyboard::options "ctrl:swapcaps"
system::keyboard::options() {
    local options="${1}"
    
    if utils::has localectl; then
        utils::quiet_err localectl set-keymap --keymap-options "${options}" || true
    fi
    
    log::info "Keyboard options set to ${options}"
}