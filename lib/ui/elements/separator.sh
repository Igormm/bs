#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/elements/separator.sh — centered horizontal rule with an optional label
# lib/ui/elements/separator.sh — центрированная горизонтальная линия с подписью
#
# Run directly to see the element / Запуск напрямую — показать элемент:
#   bs run lib/ui/elements/separator.sh

# @depends core/lang, lib/tui/tui

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_ELEMENTS_SEPARATOR" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../tui/tui.sh"

# @description Draw a centered horizontal rule.
# @description Нарисовать центрированную горизонтальную линию.
# @param $1 [optional] Label in the middle / Подпись в середине
# @param $2 [optional] Row (default: center) / Строка (по умолчанию: центр)
ui::elements::separator::draw() {
    local -r label="${1:-}"
    local -i row="${2:--1}"
    (( row < 0 )) && row=$(( TUI_LINES / 2 ))
    local -i w=$(( TUI_COLS - 4 ))
    (( w < 10 )) && w=10
    local -i bx=$(( (TUI_COLS - w) / 2 ))
    local st
    st="$(tui::style dim)"
    if is::empty "${label}"; then
        tui::put "${row}" "${bx}" "$(str::repeat '─' "${w}")" "${st}"
    else
        local -i lw=${#label}
        (( lw + 2 > w )) && lw=$(( w - 2 ))
        local -i left=$(( (w - lw - 2) / 2 ))
        (( left < 0 )) && left=0
        tui::put "${row}" "${bx}" "$(str::repeat '─' "${left}") ${label:0:${lw}} $(str::repeat '─' $(( w - left - lw - 2 )))" "${st}"
    fi
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    load "lib/tui/tui"
    tui::init
    tui::buf::clear
    ui::elements::separator::draw "Раздел / Section"
    tui::render
    tui::key_read >/dev/null
    tui::quit
fi