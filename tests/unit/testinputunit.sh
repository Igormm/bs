#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testinputunit.sh — Unit tests for lib/ui/elements/input.sh
# tests/unit/testinputunit.sh — Модульные тесты для модуля lib/ui/elements/input.sh

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/ui/elements/input"

# Build a left-to-right string of the requested buffer row (0-based).
_buf_row() {
    local -i r="$1" c
    local line=""
    for (( c = 0; c < TUI_COLS; c++ )); do
        line+="${TUI_BUF["${r},${c}"]:- }"
    done
    printf '%s' "${line}"
}

# Render an input dialog, feeding stdin through to mimic interactive input.
_run_input() {
    tui::buf::clear
    ui::elements::input::draw "$@"
    tui::render >/dev/null
}

# input::draw uses w=64, h=7 on an 80x24 terminal.
# bx=(80-64)/2=8, by=(24-7)/2=8.
# Value starts at row 10 (1-based), col 12 → buffer key "9,11".
_input_value_style() {
    printf '%s' "${TUI_BUF_STYLE["9,11"]:-}"
}

test_input_returns_value() {
    local rc=0
    ( _run_input "Input / Ввод" "alice" ) >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -eq 0" "input draw exits 0"

    tui::buf::clear
    ui::elements::input::draw "Input / Ввод" "alice" >/dev/null

    local row
    row="$(_buf_row 9)"
    testframework::assert_command "printf '%s' '${row}' | grep -Fq 'alice'" "input renders the supplied value"
}

test_input_default_value_on_empty_stdin() {
    local rc=0
    ( _run_input "Input / Ввод" "default" ) <<< "" >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -eq 0" "input with empty stdin exits 0"

    tui::buf::clear
    ui::elements::input::draw "Input / Ввод" "default" >/dev/null

    local row
    row="$(_buf_row 9)"
    testframework::assert_command "printf '%s' '${row}' | grep -Fq 'default'" "input uses the default value on empty input"
}

test_input_block_cursor_at_end() {
    tui::buf::clear
    ui::elements::input::draw "Input / Ввод" "abc" >/dev/null

    local value_style cursor_style
    value_style="$(_input_value_style)"
    cursor_style="${TUI_BUF_STYLE["9,14"]:-}"

    if [[ -z "${value_style}" ]]; then
        testframework::assert_true "true" "value cells are unstyled"
    else
        testframework::assert_true "false" "value cells are unstyled"
    fi

    if [[ -n "${cursor_style}" ]]; then
        testframework::assert_true "true" "block cursor is highlighted"
    else
        testframework::assert_true "false" "block cursor is highlighted"
    fi
}

test_input_long_value_is_clipped() {
    local value
    value="$(printf '%0.sX' {1..200})"

    local rc=0
    ( _run_input "Input / Ввод" "${value}" ) >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -eq 0" "input draw with long value exits 0"

    tui::buf::clear
    ui::elements::input::draw "Input / Ввод" "${value}" >/dev/null

    # Field width is w-6 = 58; value occupies buffer columns 11..68.
    # Column 69 (0-based) is inside the box but past the field and must stay empty.
    testframework::assert_true "-z '${TUI_BUF["9,69"]:-}'" "long input is clipped past field width"

    local row
    row="$(_buf_row 9)"
    testframework::assert_command "printf '%s' '${row}' | grep -Fq 'XXXXXXXXXX'" "clipped value is still rendered"
}

main() {
    print_header "UI Input Element Unit Tests / Модульные тесты элемента input"

    testframework::init

    testframework::section "Value rendering / Отрисовка значения"
    test_input_returns_value
    test_input_default_value_on_empty_stdin

    testframework::section "Cursor / Курсор"
    test_input_block_cursor_at_end

    testframework::section "Validation / Валидация"
    test_input_long_value_is_clipped

    testframework::summary
}

main "$@"
