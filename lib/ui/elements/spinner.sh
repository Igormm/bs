#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/elements/spinner.sh — centered braille spinner with a label
# lib/ui/elements/spinner.sh — центрированный брайлевский спиннер с подписью
#
# Run directly to see the element / Запуск напрямую — показать элемент:
#   bs run lib/ui/elements/spinner.sh

# @depends core/lang, lib/tui/tui

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_ELEMENTS_SPINNER" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../tui/tui.sh"

# @description Draw a centered spinner.
# @description Нарисовать центрированный спиннер.
# @param $1 Frame index (0-based, advances per redraw) / Номер кадра
# @param $2 Label / Подпись
ui::elements::spinner::draw() {
    local -i frame="${1:-0}"
    local -r label="${2:-}"
    local -i w=56 h=6
    (( w > TUI_COLS - 8 )) && w=$(( TUI_COLS - 8 ))

    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local st
    st="$(tui::style bold cyan)"
    tui::box "${by}" "${bx}" "${w}" "${h}" "Spinner" "${st}"
    tui::spinner $(( by + 2 )) $(( bx + 2 )) "${frame}" "$(tui::style bold cyan)"
    if is::not_empty "${label}"; then
        tui::put $(( by + 2 )) $(( bx + 4 )) "${label:0:$(( w - 6 ))}"
    fi
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    load "lib/tui/tui"
    tui::init
    demo::run() {
        local -i f
        for f in $(seq 0 9); do
            tui::buf::clear
            ui::elements::spinner::draw "${f}" "Загрузка… / Loading…"
            tui::render
            sleep 0.1
        done
    }
    demo::run
    tui::key_read >/dev/null
    tui::quit
fi
