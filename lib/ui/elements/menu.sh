#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/elements/menu.sh — centered vertical menu with selection highlight
# lib/ui/elements/menu.sh — центрированное вертикальное меню с подсветкой выбора
#
# Run directly to see the element / Запуск напрямую — показать элемент:
#   bs run lib/ui/elements/menu.sh

# @depends core/lang, lib/tui/tui

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_ELEMENTS_MENU" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../tui/tui.sh"

# @description Draw a centered vertical menu.
# @description Нарисовать центрированное вертикальное меню.
# @param $1 Title / Заголовок
# @param $2 Selected index (0-based) / Выбранный индекс
# @param $@ Items / Пункты
ui::elements::menu::draw() {
    local -r title="${1:-}"
    local -i sel="${2:-0}"
    shift 2
    local -a items=("$@")

    local -i h=$(( ${#items[@]} + 4 ))
    (( h > TUI_LINES - 4 )) && h=$(( TUI_LINES - 4 ))
    local -i w=44
    local item
    for item in "${items[@]}"; do
        (( ${#item} + 6 > w )) && w=$(( ${#item} + 6 ))
    done
    (( w > TUI_COLS - 8 )) && w=$(( TUI_COLS - 8 ))

    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local st
    st="$(tui::style bold magenta)"
    tui::box "${by}" "${bx}" "${w}" "${h}" "${title}" "${st}"
    local -i i
    for (( i = 0; i < ${#items[@]}; i++ )); do
        if (( i == sel )); then
            tui::put $(( by + 2 + i )) $(( bx + 2 )) "▸ ${items[i]}" "$(tui::style reverse cyan)"
        else
            tui::put $(( by + 2 + i )) $(( bx + 2 )) "  ${items[i]}"
        fi
    done
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    load "lib/tui/tui"
    tui::init
    tui::buf::clear
    ui::elements::menu::draw "Menu / Меню" 1 \
        "Сгенерировать / Generate" \
        "Ввести свой / Enter my own" \
        "Без пароля / No password"
    tui::render
    tui::key_read >/dev/null
    tui::quit
fi