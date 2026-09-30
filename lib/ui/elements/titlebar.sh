#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/elements/titlebar.sh — full-width title bar at the top
# lib/ui/elements/titlebar.sh — строка заголовка на всю ширину сверху
#
# Run directly to see the element / Запуск напрямую — показать элемент:
#   bs run lib/ui/elements/titlebar.sh

# @depends core/lang, lib/tui/tui

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_ELEMENTS_TITLEBAR" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../tui/tui.sh"

# @description Draw the top title bar.
# @description Нарисовать верхнюю строку заголовка.
# @param $1 Text / Текст
ui::elements::titlebar::draw() {
    local -r text="${1:-}"
    tui::titlebar "${text}" "$(tui::style bg_blue white)"
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    load "lib/tui/tui"
    tui::init
    tui::buf::clear
    ui::elements::titlebar::draw "  BS TUI Elements  •  Titlebar"
    tui::render
    tui::key_read >/dev/null
    tui::quit
fi