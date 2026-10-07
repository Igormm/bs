#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testtableunit.sh — Unit tests for lib/ui/elements/table module
# tests/unit/testtableunit.sh — Модульные тесты для модуля lib/ui/elements/table

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/ui/elements/table"

# Captured TUI render output for non-empty checks.
__render_output=""

# Reconstruct the screen buffer as rows and check for a substring.
__screen_contains() {
    local needle="$1"
    local -i r c
    for (( r = 0; r < TUI_LINES; r++ )); do
        local line=""
        for (( c = 0; c < TUI_COLS; c++ )); do
            line+="${TUI_BUF[${r},${c}]:- }"
        done
        [[ "${line}" == *"${needle}"* ]] && return 0
    done
    return 1
}

# Table should render header, separator (box frame), and data rows.
test_table_renders_header_and_rows() {
    tui::init
    TUI_COLS=80
    TUI_LINES=24
    tui::buf::clear

    testframework::assert_command \
        "ui::elements::table::draw 'Users' \
            'Name:Age:City' \
            'John:25:NYC' \
            'Jane:30:SFO' \
            'Bob:28:SEA'" \
        "table draw succeeds with header and data rows"

    __render_output="$(tui::render)"
    tui::quit

    testframework::assert_command \
        "[[ -n '${__render_output}' ]]" \
        "table produces non-empty render output"
    testframework::assert_command \
        "__screen_contains 'Name'" \
        "table buffer contains header cell Name"
    testframework::assert_command \
        "__screen_contains 'Age'" \
        "table buffer contains header cell Age"
    testframework::assert_command \
        "__screen_contains 'City'" \
        "table buffer contains header cell City"
    testframework::assert_command \
        "__screen_contains 'John'" \
        "table buffer contains data cell John"
    testframework::assert_command \
        "__screen_contains 'Jane'" \
        "table buffer contains data cell Jane"
    testframework::assert_command \
        "__screen_contains 'NYC'" \
        "table buffer contains data cell NYC"
    testframework::assert_command \
        "__screen_contains '╔'" \
        "table buffer contains box top-left corner"
    testframework::assert_command \
        "__screen_contains '╚'" \
        "table buffer contains box bottom-left corner"
}

# Empty input should return cleanly and produce no render output.
test_table_empty_input() {
    tui::init
    TUI_COLS=80
    TUI_LINES=24
    tui::buf::clear

    testframework::assert_command \
        "ui::elements::table::draw 'Empty'" \
        "table draw succeeds with no rows"

    __render_output="$(tui::render)"
    tui::quit

    testframework::assert_equal "0" "${#TUI_BUF[@]}" \
        "empty table leaves the screen buffer empty"
}

# Wide cell content should remain intact in the rendered table.
test_table_keeps_wide_cells_intact() {
    tui::init
    TUI_COLS=80
    TUI_LINES=24
    tui::buf::clear

    testframework::assert_command \
        "ui::elements::table::draw 'Wide' \
            'Identifier:Description:Value' \
            'X-001:ExtraLongDescriptionString:123456789' \
            'X-002:ШирокоеЗначение:987654321'" \
        "table draw succeeds with wide cells"

    __render_output="$(tui::render)"
    tui::quit

    testframework::assert_command \
        "__screen_contains 'ExtraLongDescriptionString'" \
        "table keeps long ASCII cell intact"
    testframework::assert_command \
        "__screen_contains 'ШирокоеЗначение'" \
        "table keeps wide Unicode cell intact"
}

main() {
    print_header "Table Element Unit Tests / Модульные тесты элемента table"

    testframework::init

    testframework::section "Table rendering / Отрисовка таблицы"
    test_table_renders_header_and_rows
    test_table_empty_input
    test_table_keeps_wide_cells_intact

    testframework::summary
}

main "$@"
