#!/usr/bin/env bs
# shellcheck shell=bash
# tests/integration/testcalc.sh — Integration tests for `bs calc`
# tests/integration/testcalc.sh — Интеграционные тесты `bs calc`
#
# Требует dc (bc/dc из любого дистрибутива Linux).
# Requires dc (bc/dc from any Linux distribution).

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly BS_LAUNCHER="${BS_PROJECT_ROOT}/bs"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

run_calc() {
    bash "${BS_LAUNCHER}" calc "$@" 2>&1
}

test_calc_help_flag() {
    local rc=0 out clean
    out="$(bash "${BS_LAUNCHER}" calc --help 2>&1)" || rc=$?
    testframework::assert_equal "0" "${rc}" "bs calc --help exits 0"
    clean="${out//\'/}"
    testframework::assert_true "'${clean}' =~ RPN" "help mentions RPN"
}

test_calc_oneshot() {
    testframework::assert_equal "14" "$(run_calc '2 3 4 * +')" "bs calc RPN arithmetic"
    testframework::assert_equal "5" "$(run_calc '2 3 +')" "bs calc auto-prints top of stack"
    testframework::assert_equal "3.1415929203" "$(run_calc '10k 355 113 /')" "bs calc honors scale"
    testframework::assert_equal "11.7849600000" "$(run_calc '10k 186000 5280 * 12 * 1000000000 /')" "bs calc light per nanosecond"
}

test_calc_explicit_print() {
    testframework::assert_equal "42" "$(run_calc '42 p')" "bs calc explicit p respected"
    testframework::assert_equal "42" "$(run_calc '42 n')" "bs calc n prints without newline"
}

test_calc_comment_no_autop() {
    testframework::assert_equal "" "$(run_calc '2 3 + # sum')" "comments disable auto-print"
}

test_calc_interactive_state() {
    local out count_5=1 count_20=1
    out="$(printf '2 3 +\n4 *\n:q\n' | bash "${BS_LAUNCHER}" calc 2>&1)"
    printf '%s\n' "${out}" | grep -qx '5' || count_5=0
    testframework::assert_equal "1" "${count_5}" "interactive prints first result"
    printf '%s\n' "${out}" | grep -qx '20' || count_20=0
    testframework::assert_equal "1" "${count_20}" "stack persists between lines"
}

main() {
    print_header "bs calc Integration Tests / Интеграционные тесты bs calc"

    testframework::init

    testframework::section "Basics / Основы"
    test_calc_help_flag
    test_calc_oneshot
    test_calc_explicit_print
    test_calc_comment_no_autop

    testframework::section "Interactive / Интерактивный режим"
    test_calc_interactive_state

    testframework::summary
}

main "$@"