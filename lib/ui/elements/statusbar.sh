#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], array, local/declare flags, BASH_* / FUNCNAME / PIPESTATUS / needs bash constructs: double-bracket [[ ]], array, local/declare flags, BASH_* / FUNCNAME / PIPESTATUS
# lib/ui/elements/statusbar.sh — full-width status bar at the bottom
# lib/ui/elements/statusbar.sh — строка статуса на всю ширину снизу
#
# Run directly to see the element / Запуск напрямую — показать элемент:
#   bs run lib/ui/elements/statusbar.sh

# @depends core/lang, lib/tui/tui

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_ELEMENTS_STATUSBAR" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../tui/tui.sh"

# @description Draw the bottom status bar.
# @description Нарисовать нижнюю строку статуса.
# @param $1 Text / Текст
ui::elements::statusbar::draw() {
    local -r text="${1:-}"
    tui::statusbar "${text}" "$(tui::style bg_black white)"
}

if bs::is_main; then
    load "lib/tui/tui"
    tui::init
    tui::buf::clear
    ui::elements::statusbar::draw "  ↑/↓ — выбор · Enter — OK · q — выход / quit"
    tui::render
    tui::key_read >/dev/null
    tui::quit
fi