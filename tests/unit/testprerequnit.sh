#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testprerequnit.sh — Unit tests for core/prereq module
# tests/unit/testprerequnit.sh — Модульные тесты для модуля core/prereq
#
# Тестирует bs::guard, bs::guard_loaded и bs::source_relative.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Test bs::guard first-load / already-loaded semantics
test_guard() {
    local result

    # First call should succeed (0)
    if bs::guard "PREREQ_TEST_X"; then
        result=0
    else
        result=1
    fi
    testframework::assert_true "${result} -eq 0" "bs::guard returns 0 on first load"

    # Variable should be set and readonly
    testframework::assert_true "-n \"${__PREREQ_TEST_X_SOURCED:-}\"" "bs::guard sets __PREREQ_TEST_X_SOURCED"

    # Second call should return 1 (already loaded)
    if bs::guard "PREREQ_TEST_X"; then
        result=0
    else
        result=1
    fi
    testframework::assert_true "${result} -eq 1" "bs::guard returns 1 on second load"
}

# Test bs::guard_loaded query
test_guard_loaded() {
    local result

    # Module not loaded yet
    if bs::guard_loaded "PREREQ_TEST_Y"; then
        result=0
    else
        result=1
    fi
    testframework::assert_true "${result} -eq 1" "bs::guard_loaded returns 1 before load"

    # Load it
    bs::guard "PREREQ_TEST_Y" || true

    # Now it should be loaded
    if bs::guard_loaded "PREREQ_TEST_Y"; then
        result=0
    else
        result=1
    fi
    testframework::assert_true "${result} -eq 0" "bs::guard_loaded returns 0 after load"
}

# Test bs::source_relative sources a file relative to the caller
test_source_relative() {
    local temp_dir
    temp_dir=$(mktemp -d)
    local helper_file="${temp_dir}/helper.sh"
    printf '%s\n' 'PREREQ_HELPER_VALUE="loaded"' >"${helper_file}"

    # Use a wrapper function so BASH_SOURCE[1] points to this file's directory
    helper::source_relative() {
        # shellcheck disable=SC1090
        source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"
    }

    # Actually test bs::source_relative by temporarily symlinking helper next to this script
    local link_file="${TEST_SCRIPT_DIR}/helper.sh"
    ln -s "${helper_file}" "${link_file}"

    bs::source_relative "helper.sh"
    testframework::assert_equal "loaded" "${PREREQ_HELPER_VALUE}" "bs::source_relative loads file relative to caller"

    rm -f "${link_file}"
    rm -rf "${temp_dir}"
}

main() {
    print_header "Core Prerequisites Unit Tests / Модульные тесты примитивов ядра"

    testframework::init

    # Load prereq directly to ensure we test the raw entry point
    source "${BS_PROJECT_ROOT}/core/prereq.sh"

    testframework::section "Guard / Защита от повторной загрузки"
    test_guard

    testframework::section "Guard Loaded / Проверка загруженности"
    test_guard_loaded

    testframework::section "Source Relative / Относительный source"
    test_source_relative

    testframework::summary
}

main "$@"
