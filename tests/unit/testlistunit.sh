#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testlistunit.sh — Unit tests for lib/ui/elements/list module
# tests/unit/testlistunit.sh — Модульные тесты для модуля lib/ui/elements/list

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Build a single buffer row (1-based) from TUI_BUF cells.
__buffer_row() {
    local -i r="$1" c
    local row=""
    for ((c = 0; c < TUI_COLS; c++)); do
        row+="${TUI_BUF["$((r - 1)),${c}"]:- }"
    done
    printf '%s' "${row}"
}

# Return 0 if any buffer row contains the given substring.
__buffer_contains() {
    local needle="$1"
    local -i r
    for ((r = 1; r <= TUI_LINES; r++)); do
        local row
        row="$(__buffer_row "${r}")"
        [[ "${row}" == *"${needle}"* ]] && return 0
    done
    return 1
}

test_load() {
    load "lib/ui/elements/list"
    testframework::assert_command "declare -f ui::elements::list::draw" "list::draw function is defined"
}

test_renders_items_and_selection() {
    TUI_COLS=80
    TUI_LINES=24
    tui::buf::clear

    ui::elements::list::draw "Test List" 0 \
        "Alpha" \
        "Beta" \
        "Gamma"

    if __buffer_contains "Test List"; then
        testframework::assert_true "true" "list draws the title"
    else
        testframework::assert_true "false" "list draws the title"
    fi

    if __buffer_contains "Alpha"; then
        testframework::assert_true "true" "list renders first item"
    else
        testframework::assert_true "false" "list renders first item"
    fi

    if __buffer_contains "Beta"; then
        testframework::assert_true "true" "list renders second item"
    else
        testframework::assert_true "false" "list renders second item"
    fi

    if __buffer_contains "Gamma"; then
        testframework::assert_true "true" "list renders third item"
    else
        testframework::assert_true "false" "list renders third item"
    fi

    if __buffer_contains "▸ Alpha"; then
        testframework::assert_true "true" "selected index 0 marks the first item"
    else
        testframework::assert_true "false" "selected index 0 marks the first item"
    fi
}

test_selection_index_changes() {
    TUI_COLS=80
    TUI_LINES=24
    tui::buf::clear

    ui::elements::list::draw "Another List" 1 \
        "First" \
        "Second" \
        "Third"

    if __buffer_contains "▸ Second"; then
        testframework::assert_true "true" "selected index 1 marks the second item"
    else
        testframework::assert_true "false" "selected index 1 marks the second item"
    fi

    if __buffer_contains "  First"; then
        testframework::assert_true "true" "unselected item keeps plain indentation"
    else
        testframework::assert_true "false" "unselected item keeps plain indentation"
    fi
}

test_empty_list() {
    TUI_COLS=80
    TUI_LINES=24
    tui::buf::clear

    ui::elements::list::draw "Empty List" 0

    if __buffer_contains "Empty List"; then
        testframework::assert_true "true" "empty list still draws the title box"
    else
        testframework::assert_true "false" "empty list still draws the title box"
    fi

    if __buffer_contains "▸"; then
        testframework::assert_true "false" "empty list has no selection marker"
    else
        testframework::assert_true "true" "empty list has no selection marker"
    fi
}

main() {
    print_header "UI Elements List Unit Tests / Модульные тесты списка элементов UI"

    testframework::init

    testframework::section "Loading / Загрузка"
    test_load

    testframework::section "Rendering / Отрисовка"
    test_renders_items_and_selection
    test_selection_index_changes
    test_empty_list

    testframework::summary
}

main "$@"
