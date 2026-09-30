#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/elements/progress.sh — centered progress bar
# lib/ui/elements/progress.sh — центрированный индикатор прогресса
#
# Run directly to see the element / Запуск напрямую — показать элемент:
#   bs run lib/ui/elements/progress.sh

# @depends core/lang, lib/tui/tui

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_ELEMENTS_PROGRESS" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../tui/tui.sh"

# @description Draw a centered progress bar.
# @description Нарисовать центрированный прогресс-бар.
# @param $1 Percent 0-100 / Проценты 0-100
# @param $2 [optional] Label / Подпись
ui::elements::progress::draw() {
    local -i pct="${1:-0}"
    local -r label="${2:-}"
    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100
    local -i w=60
    (( w > TUI_COLS - 8 )) && w=$(( TUI_COLS - 8 ))
    local -i h=7

    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local st
    st="$(tui::style bold green)"
    tui::box "${by}" "${bx}" "${w}" "${h}" "Progress / Прогресс" "${st}"
    if is::not_empty "${label}"; then
        tui::put $(( by + 2 )) $(( bx + 2 )) "${label:0:$(( w - 4 ))}"
    fi
    tui::progress $(( by + 4 )) $(( bx + 2 )) $(( w - 4 )) "${pct}"
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    load "lib/tui/tui"
    tui::init
    tui::buf::clear
    ui::elements::progress::draw 64 "Установка пакетов… / Installing packages…"
    tui::render
    tui::key_read >/dev/null
    tui::quit
fi