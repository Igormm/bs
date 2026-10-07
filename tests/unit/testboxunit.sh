#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testboxunit.sh — Unit tests for lib/ui/elements/box module
# tests/unit/testboxunit.sh — Модульные тесты для модуля lib/ui/elements/box

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/ui/elements/box"

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

# Draw a box and verify it contains rounded box-drawing characters.
test_box_draws_with_title_and_body() {
    tui::init
    TUI_COLS=80
    TUI_LINES=24
    tui::buf::clear

    testframework::assert_command \
        "ui::elements::box::draw 'Test Box' 'First line
Second line'" \
        "box draw succeeds with title and body"

    __render_output="$(tui::render)"
    tui::quit

    testframework::assert_command \
        "[[ -n '${__render_output}' ]]" \
        "box produces non-empty render output"
    testframework::assert_command \
        "__screen_contains '╭'" \
        "box buffer contains top-left rounded corner"
    testframework::assert_command \
        "__screen_contains '╰'" \
        "box buffer contains bottom-left rounded corner"
    testframework::assert_command \
        "__screen_contains '─'" \
        "box buffer contains horizontal border"
    testframework::assert_command \
        "__screen_contains '│'" \
        "box buffer contains vertical border"
    testframework::assert_command \
        "__screen_contains 'Test Box'" \
        "box buffer contains the title"
    testframework::assert_command \
        "__screen_contains 'First line'" \
        "box buffer contains the body"
}

main() {
    print_header "Box Element Unit Tests / Модульные тесты элемента box"

    testframework::init

    testframework::section "Box drawing / Рисование рамки"
    test_box_draws_with_title_and_body

    testframework::summary
}

main "$@"
