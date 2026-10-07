#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testprogressunit.sh — Unit tests for lib/ui/elements/progress
# tests/unit/testprogressunit.sh — Модульные тесты для lib/ui/elements/progress

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

# Count occurrences of a single UTF-8 character in a string.
__count_char() {
    local text="$1" ch="$2"
    printf '%s' "${text}" | awk -v c="${ch}" '{ print gsub(c,"") }'
}

# Test that a label is rendered into the output.
test_progress_renders_label() {
    tui::buf::clear
    ui::elements::progress::draw 50 "Installing packages"
    local flat
    flat="$(__buffer_to_string)"
    if printf '%s' "${flat}" | grep -q "Installing packages"; then
        testframework::assert_true "true" "progress output contains label"
    else
        testframework::assert_true "false" "progress output contains label"
    fi
}

# Test filled/empty ratio at 50% (inner bar width is 48 cells).
test_progress_ratio_50() {
    tui::buf::clear
    ui::elements::progress::draw 50 ""
    local flat filled empty
    flat="$(__buffer_to_string)"
    filled="$(__count_char "${flat}" "█")"
    empty="$(__count_char "${flat}" "░")"
    testframework::assert_equal "24" "${filled}" "50% filled blocks count"
    testframework::assert_equal "24" "${empty}" "50% empty blocks count"
}

# Test 0% renders as fully empty.
test_progress_zero() {
    tui::buf::clear
    ui::elements::progress::draw 0 ""
    local flat filled empty
    flat="$(__buffer_to_string)"
    filled="$(__count_char "${flat}" "█")"
    empty="$(__count_char "${flat}" "░")"
    testframework::assert_equal "0" "${filled}" "0% filled blocks count"
    testframework::assert_equal "48" "${empty}" "0% empty blocks count"
}

# Test 100% renders as fully filled.
test_progress_max() {
    tui::buf::clear
    ui::elements::progress::draw 100 ""
    local flat filled empty
    flat="$(__buffer_to_string)"
    filled="$(__count_char "${flat}" "█")"
    empty="$(__count_char "${flat}" "░")"
    testframework::assert_equal "48" "${filled}" "100% filled blocks count"
    testframework::assert_equal "0" "${empty}" "100% empty blocks count"
}

# Test negative values are clamped to 0.
test_progress_negative_clamped() {
    tui::buf::clear
    ui::elements::progress::draw -10 ""
    local flat filled empty
    flat="$(__buffer_to_string)"
    filled="$(__count_char "${flat}" "█")"
    empty="$(__count_char "${flat}" "░")"
    testframework::assert_equal "0" "${filled}" "negative percent filled blocks count"
    testframework::assert_equal "48" "${empty}" "negative percent empty blocks count"
}

# Test values over 100 are clamped to 100.
test_progress_over_clamped() {
    tui::buf::clear
    ui::elements::progress::draw 200 ""
    local flat filled empty
    flat="$(__buffer_to_string)"
    filled="$(__count_char "${flat}" "█")"
    empty="$(__count_char "${flat}" "░")"
    testframework::assert_equal "48" "${filled}" "over-100 percent filled blocks count"
    testframework::assert_equal "0" "${empty}" "over-100 percent empty blocks count"
}

# Test non-numeric input is rejected (run in a subshell so the set -u
# arithmetic error does not abort the test runner).
test_progress_invalid_input() {
    local flat
    if flat="$(ui::elements::progress::draw 'abc' 'label' 2>/dev/null)"; then
        testframework::assert_true "false" "non-numeric percent is rejected"
    else
        testframework::assert_true "true" "non-numeric percent is rejected"
    fi
}

main() {
    print_header "UI Elements Progress Unit Tests / Модульные тесты прогресса"

    testframework::init

    testframework::section "Module Loading / Загрузка модуля"
    load "lib/ui/elements/progress"
    testframework::assert_true "$(declare -f ui::elements::progress::draw >/dev/null && printf true || printf false)" "progress module loaded"

    testframework::section "Rendering / Отрисовка"
    test_progress_renders_label

    testframework::section "Ratio / Соотношение заполнения"
    test_progress_ratio_50
    test_progress_zero
    test_progress_max

    testframework::section "Invalid Input / Некорректный ввод"
    test_progress_negative_clamped
    test_progress_over_clamped
    test_progress_invalid_input

    testframework::summary
}

main "$@"
