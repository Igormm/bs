#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/elements/message.sh — centered info/success/warning/error banner
# lib/ui/elements/message.sh — центрированный баннер info/success/warning/error
#
# Run directly to see the element / Запуск напрямую — показать элемент:
#   bs run lib/ui/elements/message.sh

# @depends core/lang, lib/tui/tui

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_ELEMENTS_MESSAGE" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../tui/tui.sh"

# @description Draw a centered colored banner.
# @description Нарисовать центрированный цветной баннер.
# @param $1 Level: info|success|warning|error
# @param $2 Text / Текст
ui::elements::message::draw() {
    local -r level="${1:-info}" text="${2:-}"
    local -i h=6
    (( h > TUI_LINES - 2 )) && h=$(( TUI_LINES - 2 ))
    local -i w=$(( ${#text} + 6 ))
    (( w > TUI_COLS - 8 )) && w=$(( TUI_COLS - 8 ))
    (( w < 30 )) && w=30

    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local st color
    case "${level}" in
        success) st="$(tui::style bold green)"  color=green ;;
        warning) st="$(tui::style bold yellow)" color=yellow ;;
        error)   st="$(tui::style bold red)"    color=red ;;
        *)       st="$(tui::style bold cyan)"   color=cyan ;;
    esac
    tui::box "${by}" "${bx}" "${w}" "${h}" "Message / Сообщение" "${st}"
    tui::put $(( by + 2 )) $(( bx + 2 )) "${text:0:$(( w - 4 ))}"
    tui::put $(( by + 4 )) $(( bx + 2 )) "  ${level}" "$(tui::style "${color}")"
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    load "lib/tui/tui"
    tui::init
    tui::buf::clear
    ui::elements::message::draw success "Готово! / Done!"
    tui::render
    tui::key_read >/dev/null
    tui::quit
fi