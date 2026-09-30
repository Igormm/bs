#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/elements/table.sh — centered table with header and aligned columns
# lib/ui/elements/table.sh — центрированная таблица с шапкой и выровненными колонками
#
# Rows are colon-separated cells: "Name:Age:City". The first row is the header.
# Строки — ячейки через двоеточие: "Name:Age:City". Первая строка — шапка.
#
# Run directly to see the element / Запуск напрямую — показать элемент:
#   bs run lib/ui/elements/table.sh

# @depends core/lang, lib/tui/tui

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_ELEMENTS_TABLE" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../tui/tui.sh"

# @description Draw a centered table with a header.
# @description Нарисовать центрированную таблицу с шапкой.
# @param $1 Title / Заголовок
# @param $@ Rows, colon-separated; first = header / Строки через ':'; первая = шапка
ui::elements::table::draw() {
    local -r title="${1:-}"
    shift
    local -a rows=("$@")
    (( ${#rows[@]} == 0 )) && return 0

    # Ширины колонок / column widths
    local -a widths=()
    local row i cell
    for row in "${rows[@]}"; do
        local -a cells=()
        IFS=':' read -ra cells <<< "${row}"
        for i in "${!cells[@]}"; do
            (( ${#cells[i]} > ${widths[i]:-0} )) && widths[i]=${#cells[i]}
        done
    done

    local -i total=1
    local w
    for w in "${widths[@]}"; do
        (( total += w + 3 ))
    done
    local -i h=$(( ${#rows[@]} + 4 ))
    (( h > TUI_LINES - 2 )) && h=$(( TUI_LINES - 2 ))
    (( total > TUI_COLS - 8 )) && total=$(( TUI_COLS - 8 ))

    tui::center "${total}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local st
    st="$(tui::style bold magenta)"
    tui::box "${by}" "${bx}" "${total}" "${h}" "${title}" "${st}"

    local -i row_i=$(( by + 2 ))
    for row in "${rows[@]}"; do
        local -a cells=()
        IFS=':' read -ra cells <<< "${row}"
        local -i col="${bx}"
        for i in "${!cells[@]}"; do
            if (( row_i == by + 2 )); then
                tui::put "${row_i}" "$(( col + 2 ))" "$(printf '%-*s' "${widths[i]:-0}" "${cells[i]}")" "$(tui::style bold)"
            else
                tui::put "${row_i}" "$(( col + 2 ))" "$(printf '%-*s' "${widths[i]:-0}" "${cells[i]}")"
            fi
            (( col += widths[i] + 3 ))
        done
        (( row_i += 1 ))
    done
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    load "lib/tui/tui"
    tui::init
    tui::buf::clear
    ui::elements::table::draw "Table / Таблица" \
        "Name:Age:City" \
        "John:25:NYC" \
        "Jane:30:SFO" \
        "Bob:28:SEA"
    tui::render
    tui::key_read >/dev/null
    tui::quit
fi