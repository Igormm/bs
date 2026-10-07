#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testseparatorunit.sh — Unit tests for lib/ui/elements/separator module
# tests/unit/testseparatorunit.sh — Модульные тесты для модуля lib/ui/elements/separator

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/ui/elements/separator"

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

# Empty label should produce a horizontal rule.
test_separator_empty_label() {
    tui::init
    TUI_COLS=80
    TUI_LINES=24
    tui::buf::clear

    testframework::assert_command \
        "ui::elements::separator::draw" \
        "separator draw succeeds with no arguments"

    __render_output="$(tui::render)"
    tui::quit

    testframework::assert_command \
        "[[ -n '${__render_output}' ]]" \
        "empty-label separator produces non-empty render output"
    testframework::assert_command \
        "__screen_contains '─'" \
        "empty-label separator contains horizontal rule character"
}

# Labeled separator should include the label text.
test_separator_with_label() {
    tui::init
    TUI_COLS=80
    TUI_LINES=24
    tui::buf::clear

    testframework::assert_command \
        "ui::elements::separator::draw 'Section'" \
        "separator draw succeeds with a label"

    __render_output="$(tui::render)"
    tui::quit

    testframework::assert_command \
        "__screen_contains 'Section'" \
        "labeled separator contains the label text"
    testframework::assert_command \
        "__screen_contains '─'" \
        "labeled separator contains horizontal rule character"
}

# Explicit row argument should be accepted without error.
test_separator_with_row() {
    tui::init
    TUI_COLS=80
    TUI_LINES=24
    tui::buf::clear

    testframework::assert_command \
        "ui::elements::separator::draw 'Row 5' 5" \
        "separator draw succeeds with explicit row"

    __render_output="$(tui::render)"
    tui::quit

    testframework::assert_command \
        "__screen_contains 'Row 5'" \
        "separator with explicit row contains the label"
}

# Very narrow terminal should not crash the separator.
test_separator_narrow_terminal() {
    tui::init
    TUI_COLS=8
    TUI_LINES=12
    tui::buf::clear

    testframework::assert_command \
        "ui::elements::separator::draw 'Hi'" \
        "separator draw succeeds on a narrow terminal"

    __render_output="$(tui::render)"
    tui::quit

    testframework::assert_command \
        "__screen_contains 'Hi'" \
        "narrow-terminal separator contains the label"
}

main() {
    print_header "Separator Element Unit Tests / Модульные тесты элемента separator"

    testframework::init

    testframework::section "Separator rendering / Отрисовка разделителя"
    test_separator_empty_label
    test_separator_with_label
    test_separator_with_row
    test_separator_narrow_terminal

    testframework::summary
}

main "$@"
