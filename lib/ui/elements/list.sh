#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/elements/list.sh — centered selectable list with viewport scrolling
# lib/ui/elements/list.sh — центрированный список с выбором и прокруткой
#
# Run directly to see the element / Запуск напрямую — показать элемент:
#   bs run lib/ui/elements/list.sh

# @depends core/lang, lib/tui/tui

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_ELEMENTS_LIST" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../tui/tui.sh"

# @description Draw a centered selectable list.
# @description Нарисовать центрированный список с выбором.
# @param $1 Title / Заголовок
# @param $2 Selected index (0-based) / Выбранный индекс
# @param $@ Items / Пункты
ui::elements::list::draw() {
    local -r title="${1:-}"
    local -i sel="${2:-0}"
    shift 2
    local -a items=("$@")

    local -i h=$(( ${#items[@]} + 4 ))
    (( h > TUI_LINES - 4 )) && h=$(( TUI_LINES - 4 ))
    (( h < 6 )) && h=6
    local -i w=56
    local item
    for item in "${items[@]}"; do
        (( ${#item} + 6 > w )) && w=$(( ${#item} + 6 ))
    done
    (( w > TUI_COLS - 8 )) && w=$(( TUI_COLS - 8 ))

    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local st
    st="$(tui::style bold cyan)"
    tui::box "${by}" "${bx}" "${w}" "${h}" "${title}" "${st}"
    tui::list $(( by + 2 )) $(( bx + 2 )) $(( w - 4 )) $(( h - 3 )) items "${sel}"
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    load "lib/tui/tui"
    tui::init
    tui::buf::clear
    ui::elements::list::draw "List / Список" 2 \
        "Первый пункт / First item" \
        "Второй пункт / Second item" \
        "Третий пункт / Third item" \
        "Четвёртый пункт / Fourth item"
    tui::render
    tui::key_read >/dev/null
    tui::quit
fi