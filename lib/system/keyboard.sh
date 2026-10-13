#!/usr/bin/env bs
# shellcheck shell=bash
# keyboard.sh — Keyboard layout configuration for system setup / Конфигурация раскладки
# клавиатуры для настройки системы
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_KEYBOARD" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @description Change one X11 keymap field, keeping the others (localectl
# set-x11-keymap takes layout, model, variant, options together) / Изменить одно поле
# X11-раскладки, сохранив остальные (localectl set-x11-keymap принимает layout, model,
# variant, options вместе)
# @param $1 Field: layout|model|variant|options / Поле
# @param $2 New value / Новое значение
system::keyboard::__x11_set() {
    local -r field="${1}" value="${2}"
    local layout="" model="" variant="" options="" line key val

    if ! utils::has localectl; then
        log::warn "localectl not available: cannot set keyboard ${field}"
        return "${E_ERROR}"
    fi

    while IFS= read -r line; do
        key="${line%%:*}"
        val="${line#*:}"
        key="${key//[[:space:]]/}"
        val="${val#"${val%%[![:space:]]*}"}"
        [[ "${val}" == "n/a" ]] && val=""
        case "${key}" in
            X11Layout)  layout="${val}" ;;
            X11Model)   model="${val}" ;;
            X11Variant) variant="${val}" ;;
            X11Options) options="${val}" ;;
        esac
    done < <(utils::attempt localectl status)

    case "${field}" in
        layout)  layout="${value}" ;;
        model)   model="${value}" ;;
        variant) variant="${value}" ;;
        options) options="${value}" ;;
    esac

    if is::empty "${layout}"; then
        log::error "Current X11 layout unknown: cannot set ${field}"
        return "${E_ERROR}"
    fi
    if ! utils::quiet localectl set-x11-keymap "${layout}" "${model}" "${variant}" "${options}"; then
        log::error "localectl set-x11-keymap failed"
        return "${E_ERROR}"
    fi
    return 0
}

# @description Set keyboard layout for console and X11 / Установить раскладку клавиатуры
# для консоли и X11
# @param $1 Keyboard layout code (e.g., "us", "ru") / Код раскладки клавиатуры (например,
# "us", "ru")
# @example
#   system::keyboard::layout "us"
system::keyboard::layout() {
    local layout="${1:-us}"
    
    if [[ ! "${layout}" =~ ^[A-Za-z0-9_,.@-]+$ ]]; then
        log::warn "Invalid keyboard layout: ${layout}"
        return "${E_ERROR}"
    fi
    
    local done_any=0
    if utils::has localectl; then
        # Both calls must work: console keymap and X11 keymap / Оба вызова должны
        # сработать: консольная и X11-раскладка
        if ! utils::quiet localectl set-keymap "${layout}"; then
            log::error "localectl set-keymap ${layout} failed"
            return "${E_ERROR}"
        fi
        if ! utils::quiet localectl set-x11-keymap "${layout}"; then
            log::error "localectl set-x11-keymap ${layout} failed"
            return "${E_ERROR}"
        fi
        done_any=1
    else
        if utils::has loadkeys && utils::quiet loadkeys "${layout}"; then
            done_any=1
        fi
        if utils::has setxkbmap && utils::quiet setxkbmap "${layout}"; then
            done_any=1
        fi
    fi
    
    if (( done_any == 0 )); then
        log::error "No tool changed the keyboard layout to ${layout}"
        return "${E_ERROR}"
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
    system::keyboard::__x11_set model "${model}" || return "${E_ERROR}"
    log::info "Keyboard model set to ${model}"
}

# @description Set keyboard variant / Установить вариант клавиатуры
# @param $1 Keyboard variant (e.g., "dvorak", "colemak") / Вариант клавиатуры (например,
# "dvorak", "colemak")
# @example
#   system::keyboard::variant "dvorak"
system::keyboard::variant() {
    local variant="${1:-}"
    system::keyboard::__x11_set variant "${variant}" || return "${E_ERROR}"
    log::info "Keyboard variant set to ${variant}"
}

# @description Set keyboard options / Установить опции клавиатуры
# @param $1 Keyboard options (e.g., "ctrl:swapcaps") / Опции клавиатуры (например,
# "ctrl:swapcaps")
# @example
#   system::keyboard::options "ctrl:swapcaps"
system::keyboard::options() {
    local options="${1:-}"
    system::keyboard::__x11_set options "${options}" || return "${E_ERROR}"
    log::info "Keyboard options set to ${options}"
}
