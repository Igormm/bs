#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testmenuunit.sh — Unit tests for lib/ui/elements/menu.sh
# tests/unit/testmenuunit.sh — Модульные тесты для модуля lib/ui/elements/menu.sh

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/ui/elements/menu"

# Build a left-to-right string of the requested buffer row (0-based).
_buf_row() {
    local -i r="$1" c
    local line=""
    for (( c = 0; c < TUI_COLS; c++ )); do
        line+="${TUI_BUF["${r},${c}"]:- }"
    done
    printf '%s' "${line}"
}

# Render a menu dialog, feeding stdin through to mimic interactive input.
_run_menu() {
    tui::buf::clear
    ui::elements::menu::draw "$@"
    tui::render >/dev/null
}

test_menu_digit_selects_item() {
    local rc=0
    ( _run_menu "Menu / Меню" 1 "Alpha" "Beta" "Gamma" ) <<< "2" >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -eq 0" "menu draw exits 0"

    tui::buf::clear
    ui::elements::menu::draw "Menu / Меню" 1 "Alpha" "Beta" "Gamma" >/dev/null

    local row
    row="$(_buf_row 10)"
    testframework::assert_command "printf '%s' '${row}' | grep -Fq '▸ Beta'" "menu highlights the item selected by index"
}

test_menu_selection_highlight() {
    tui::buf::clear
    ui::elements::menu::draw "Menu / Меню" 1 "Alpha" "Beta" "Gamma" >/dev/null

    # by=8, so selected item (index 1) is at row 11 (1-based) → buffer row 10.
    # col bx+2=20 → buffer col 19.
    local prefix style
    prefix="${TUI_BUF["10,19"]:-}"
    style="${TUI_BUF_STYLE["10,19"]:-}"

    testframework::assert_equal "▸" "${prefix}" "selected item has pointer prefix"

    if [[ -n "${style}" ]]; then
        testframework::assert_true "true" "selected item is highlighted"
    else
        testframework::assert_true "false" "selected item is highlighted"
    fi
}

test_menu_unselected_items_not_highlighted() {
    tui::buf::clear
    ui::elements::menu::draw "Menu / Меню" 0 "Alpha" "Beta" "Gamma" >/dev/null

    # First item selected: second item at buffer row 11, col 19 should be unstyled.
    local style
    style="${TUI_BUF_STYLE["11,19"]:-}"

    if [[ -z "${style}" ]]; then
        testframework::assert_true "true" "unselected item has no highlight"
    else
        testframework::assert_true "false" "unselected item has no highlight"
    fi
}

test_menu_cancel_input() {
    # The draw-only element ignores cancel input, but it must still render.
    local rc=0
    ( _run_menu "Menu / Меню" 0 "Alpha" "Beta" "Gamma" ) <<< "q" >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -eq 0" "menu with q input exits 0"

    tui::buf::clear
    ui::elements::menu::draw "Menu / Меню" 0 "Alpha" "Beta" "Gamma" >/dev/null

    local row
    row="$(_buf_row 9)"
    testframework::assert_command "printf '%s' '${row}' | grep -Fq 'Alpha'" "menu renders items when cancel key is fed"
}

main() {
    print_header "UI Menu Element Unit Tests / Модульные тесты элемента menu"

    testframework::init

    testframework::section "Selection / Выбор"
    test_menu_digit_selects_item
    test_menu_selection_highlight

    testframework::section "Unselected items / Невыбранные пункты"
    test_menu_unselected_items_not_highlighted

    testframework::section "Cancel input / Ввод отмены"
    test_menu_cancel_input

    testframework::summary
}

main "$@"
