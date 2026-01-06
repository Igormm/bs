#!/usr/bin/env bs
# keyboard.sh — Keyboard layout configuration for system setup / Конфигурация раскладки
# клавиатуры для настройки системы

# @description Set keyboard layout for console and X11 / Установить раскладку клавиатуры
# для консоли и X11
# @param $1 Keyboard layout code (e.g., "us", "ru") / Код раскладки клавиатуры (например,
# "us", "ru")
# @example
#   system::keyboard::layout "us"
system::keyboard::layout() {
    local layout="${1:-us}"
    
    # For systemd-based systems with localectl / Для систем на базе systemd с localectl
    if command -v localectl >/dev/null 2>&1; then
        localectl set-keymap "${layout}" 2>/dev/null || true
        # For X11 sessions / Для сессий X11
        localectl set-x11-keymap "${layout}" 2>/dev/null || true
    else
        # Fallback for non-systemd systems / Резервный вариант для систем без systemd
        if command -v loadkeys >/dev/null 2>&1; then
            loadkeys "${layout}" 2>/dev/null || true
        fi
        
        # For X11 systems / Для систем X11
        if command -v setxkbmap >/dev/null 2>&1; then
            setxkbmap "${layout}" 2>/dev/null || true
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
    
    if command -v localectl >/dev/null 2>&1; then
        localectl set-keymap --keymap-model "${model}" 2>/dev/null || true
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
    
    if command -v localectl >/dev/null 2>&1; then
        localectl set-keymap --keymap-variant "${variant}" 2>/dev/null || true
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
    
    if command -v localectl >/dev/null 2>&1; then
        localectl set-keymap --keymap-options "${options}" 2>/dev/null || true
    fi
    
    log::info "Keyboard options set to ${options}"
}