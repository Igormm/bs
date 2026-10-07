#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testtitlebarunit.sh — Unit tests for lib/ui/elements/titlebar module
# tests/unit/testtitlebarunit.sh — Модульные тесты для модуля lib/ui/elements/titlebar

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

test_load() {
    load "lib/ui/elements/titlebar"
    testframework::assert_command "declare -f ui::elements::titlebar::draw" "titlebar::draw function is defined"
}

test_renders_title() {
    TUI_COLS=60
    TUI_LINES=3
    tui::buf::clear

    ui::elements::titlebar::draw "My Application"

    local expected
    expected="$(printf '%-*s' "${TUI_COLS}" "My Application")"
    testframework::assert_equal "${expected}" "$(__buffer_row 1)" "titlebar renders the title at the top"
}

test_empty_title() {
    TUI_COLS=60
    TUI_LINES=3
    tui::buf::clear

    ui::elements::titlebar::draw ""

    local expected
    expected="$(printf '%*s' "${TUI_COLS}" "")"
    testframework::assert_equal "${expected}" "$(__buffer_row 1)" "titlebar with empty title is blank"
}

test_custom_width() {
    TUI_COLS=40
    TUI_LINES=3
    tui::buf::clear

    ui::elements::titlebar::draw "Short"

    local expected
    expected="$(printf '%-*s' "${TUI_COLS}" "Short")"
    testframework::assert_equal "${expected}" "$(__buffer_row 1)" "titlebar respects custom terminal width"
}

main() {
    print_header "UI Elements Titlebar Unit Tests / Модульные тесты строки заголовка"

    testframework::init

    testframework::section "Loading / Загрузка"
    test_load

    testframework::section "Rendering / Отрисовка"
    test_renders_title
    test_empty_title
    test_custom_width

    testframework::summary
}

main "$@"
