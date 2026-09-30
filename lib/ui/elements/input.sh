#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/elements/input.sh — centered input field with a block cursor
# lib/ui/elements/input.sh — центрированное поле ввода с блочным курсором
#
# Run directly to see the element / Запуск напрямую — показать элемент:
#   bs run lib/ui/elements/input.sh

# @depends core/lang, lib/tui/tui

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_ELEMENTS_INPUT" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../tui/tui.sh"

# @description Draw a centered input field.
# @description Нарисовать центрированное поле ввода.
# @param $1 Title / Заголовок
# @param $2 Current value / Текущее значение
# @param $3 [optional] Cursor position / Позиция курсора
ui::elements::input::draw() {
    local -r title="${1:-}" value="${2:-}" cur="${3:-${#2}}"
    local -i w=64 h=7
    (( w > TUI_COLS - 8 )) && w=$(( TUI_COLS - 8 ))

    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local st
    st="$(tui::style bold yellow)"
    tui::box "${by}" "${bx}" "${w}" "${h}" "${title}" "${st}"
    tui::put $(( by + 2 )) $(( bx + 2 )) "▸" "$(tui::style bold)"
    tui::input $(( by + 2 )) $(( bx + 4 )) $(( w - 6 )) "${value}" "${cur}"
    tui::put $(( by + 4 )) $(( bx + 2 )) "Enter — OK · ESC — отмена / cancel" "$(tui::style dim)"
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    load "lib/tui/tui"
    tui::init
    tui::buf::clear
    ui::elements::input::draw "Input / Ввод" "пример текста / sample text"
    tui::render
    tui::key_read >/dev/null
    tui::quit
fi