#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testspinnerunit.sh — Unit tests for lib/ui/elements/spinner
# tests/unit/testspinnerunit.sh — Модульные тесты для lib/ui/elements/spinner

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Flatten the TUI buffer into a single string ordered by row and column.
__buffer_to_string() {
    local key
    local -a sorted=()
    while IFS= read -r key; do
        sorted+=("${key}")
    done < <(printf '%s\n' "${!TUI_BUF[@]}" | sort -t',' -k1,1n -k2,2n)
    for key in "${sorted[@]}"; do
        printf '%s' "${TUI_BUF[${key}]}"
    done
}

# Test that a labeled spinner renders the label.
test_spinner_renders_label() {
    tui::buf::clear
    ui::elements::spinner::draw 0 "Loading… / Loading..."
    local flat
    flat="$(__buffer_to_string)"
    if printf '%s' "${flat}" | grep -q "Loading"; then
        testframework::assert_true "true" "spinner output contains label"
    else
        testframework::assert_true "false" "spinner output contains label"
    fi
}

# Test that an empty label is safe and still draws a frame.
test_spinner_empty_label() {
    tui::buf::clear
    ui::elements::spinner::draw 0 ""
    local flat
    flat="$(__buffer_to_string)"
    testframework::assert_true "${#flat} -gt 0" "empty label still renders output"
}

# Test that multiple frames can be drawn without hanging (dry-run / stop path).
test_spinner_frames_no_hang() {
    local f flat
    for f in 0 1 2 3 4 5 6 7 8 9; do
        tui::buf::clear
        ui::elements::spinner::draw "${f}" "Frame ${f}"
        flat="$(__buffer_to_string)"
        testframework::assert_true "${#flat} -gt 0" "frame ${f} renders output"
    done
}

main() {
    print_header "UI Elements Spinner Unit Tests / Модульные тесты спиннера"

    testframework::init

    testframework::section "Module Loading / Загрузка модуля"
    load "lib/ui/elements/spinner"
    testframework::assert_true "$(declare -f ui::elements::spinner::draw >/dev/null && printf true || printf false)" "spinner module loaded"

    testframework::section "Rendering / Отрисовка"
    test_spinner_renders_label
    test_spinner_empty_label
    test_spinner_frames_no_hang

    testframework::summary
}

main "$@"
