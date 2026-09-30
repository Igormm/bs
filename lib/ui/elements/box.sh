#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/elements/box.sh — centered framed box with title and multi-line text
# lib/ui/elements/box.sh — центрированная рамка с заголовком и многострочным текстом
#
# Draws into the TUI buffer; the caller wraps with tui::buf::clear + tui::render.
# Рисует в буфер TUI; вызывающий оборачивает tui::buf::clear + tui::render.
#
# Run directly to see the element / Запуск напрямую — показать элемент:
#   bs run lib/ui/elements/box.sh

# @depends core/lang, lib/tui/tui

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_ELEMENTS_BOX" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../tui/tui.sh"

# @description Draw a centered framed box with a title.
# @description Нарисовать центрированную рамку с заголовком.
# @param $1 Title / Заголовок
# @param $2 Text (multi-line, \n разделяет строки / \n separates lines)
# @param $3 [optional] Border style: double|single|rounded|dashed|thick (default: rounded)
ui::elements::box::draw() {
    local -r title="${1:-}" text="${2:-}" style="${3:-rounded}"
    local -i h=4
    local line
    while IFS= read -r line; do
        (( h += 1 ))
    done <<< "${text}"
    (( h > TUI_LINES - 2 )) && h=$(( TUI_LINES - 2 ))
    tui::center $(( TUI_COLS - 8 )) "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    tui::border::set "${style}"
    local st
    st="$(tui::style bold cyan)"
    tui::box "${by}" "${bx}" $(( TUI_COLS - 8 )) "${h}" "${title}" "${st}"
    local -i row=$(( by + 2 ))
    while IFS= read -r line; do
        tui::put "$(( row++ ))" $(( bx + 2 )) "${line:0:$(( TUI_COLS - 12 ))}"
    done <<< "${text}"
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    load "lib/tui/tui"
    tui::init
    tui::buf::clear
    ui::elements::box::draw "Box / Рамка" "Центрированная рамка с заголовком
Centered framed box with a title
и многострочным содержимым / and multi-line content"
    tui::render
    tui::key_read >/dev/null
    tui::quit
fi