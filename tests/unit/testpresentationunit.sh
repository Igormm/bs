#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testpresentationunit.sh — Unit tests for lib/ui/presentation
# tests/unit/testpresentationunit.sh — Модульные тесты lib/ui/presentation
#
# Регрессия: presentation::table падала под set -u
# («assignment to invalid subscript range» у локальных массивов без границ).
# Regression: presentation::table crashed under set -u
# (local arrays without bounds — "assignment to invalid subscript range").

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/ui/presentation"

# Test table renders header, separator and rows
test_table_basic() {
    local out
    out="$(presentation::table "Name:Age" "John:25" "Jane:30" 2>&1)" || {
        testframework::assert_true "false" "table runs without error"
        return 0
    }
    testframework::assert_true "true" "table runs without error"

    local first_line
    first_line="$(printf '%s\n' "${out}" | sed -n '1p')"
    testframework::assert_equal "| Name | Age |" "${first_line}" "table renders header row"

    local sep_line
    sep_line="$(printf '%s\n' "${out}" | sed -n '2p')"
    testframework::assert_true "'${sep_line}' =~ ^\+-" "table renders separator line"

    local john_line
    john_line="$(printf '%s\n' "${out}" | sed -n '3p')"
    testframework::assert_true "'${john_line}' =~ John" "table renders data rows"
}

# Test table tolerates differing column widths
test_table_ragged_columns() {
    local out
    out="$(presentation::table "a:bbb" "cccc:d" 2>&1)" || {
        testframework::assert_true "false" "ragged columns run without error"
        return 0
    }
    testframework::assert_true "true" "ragged columns run without error"

    local cccc_line
    cccc_line="$(printf '%s\n' "${out}" | sed -n '3p')"
    testframework::assert_true "'${cccc_line}' =~ cccc" "wide cell kept intact"
}

# Test table returns 0 with empty input (no crash)
test_table_empty() {
    local rc=0
    presentation::table >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "table with no rows exits 0"
}

# Test table runs in strict mode (set -u regression)
test_table_under_set_u() {
    local out
    out="$(presentation::table "X:Y" "1:2" 2>&1)" || {
        testframework::assert_true "false" "table survives set -u"
        return 0
    }
    testframework::assert_true "true" "table survives set -u"
}

main() {
    print_header "Presentation Unit Tests / Модульные тесты presentation"

    testframework::init

    testframework::section "presentation::table / Таблица"
    test_table_basic
    test_table_ragged_columns
    test_table_empty
    test_table_under_set_u

    testframework::summary
}

main "$@"