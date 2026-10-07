#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/teststatusbarunit.sh — Unit tests for lib/ui/elements/statusbar module
# tests/unit/teststatusbarunit.sh — Модульные тесты для модуля lib/ui/elements/statusbar

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
    load "lib/ui/elements/statusbar"
    testframework::assert_command "declare -f ui::elements::statusbar::draw" "statusbar::draw function is defined"
}

test_single_segment() {
    TUI_COLS=60
    TUI_LINES=5
    tui::buf::clear

    ui::elements::statusbar::draw "Ready"

    local expected
    expected="$(printf '%-*s' "${TUI_COLS}" "Ready")"
    testframework::assert_equal "${expected}" "$(__buffer_row "${TUI_LINES}")" "statusbar renders a single segment at the bottom"
}

test_multiple_segments() {
    TUI_COLS=60
    TUI_LINES=5
    tui::buf::clear

    local text="CPU: 12%  MEM: 34%  DISK: 56%"
    ui::elements::statusbar::draw "${text}"

    local expected
    expected="$(printf '%-*s' "${TUI_COLS}" "${text}")"
    testframework::assert_equal "${expected}" "$(__buffer_row "${TUI_LINES}")" "statusbar renders multiple segments at the bottom"
}

main() {
    print_header "UI Elements Statusbar Unit Tests / Модульные тесты строки статуса"

    testframework::init

    testframework::section "Loading / Загрузка"
    test_load

    testframework::section "Rendering / Отрисовка"
    test_single_segment
    test_multiple_segments

    testframework::summary
}

main "$@"
