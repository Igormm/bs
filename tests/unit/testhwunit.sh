#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testhwunit.sh — Unit tests for lib/hw module
# tests/unit/testhwunit.sh — Модульные тесты для модуля lib/hw

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Test module loading
test_module_loaded() {
    load "lib/system/hw"
    testframework::assert_true "${SYSTEM_HW_LOADED:-}" "Module loaded"
}

# Test data functions on any Linux
test_cpu_functions() {
    local count
    count="$(system::hw::cpu_threads)"
    testframework::assert_true "'${count}' =~ ^[0-9]+$" "system::hw::cpu_threads returns a number"
    testframework::assert_true "${count} -ge 1" "system::hw::cpu_threads is at least 1"

    local model
    model="$(system::hw::cpu_model)"
    testframework::assert_true "-n \"${model}\"" "system::hw::cpu_model is non-empty"

    local cpu_out
    cpu_out="$(system::hw::cpu)"
    testframework::assert_true "-n \"${cpu_out}\"" "system::hw::cpu prints a summary"

    local mem
    mem="$(system::hw::mem_total)"
    testframework::assert_true "'${mem}' =~ ^[0-9]+$" "system::hw::mem_total returns MiB number"
    testframework::assert_true "${mem} -ge 1" "system::hw::mem_total is positive"

    local avail
    avail="$(system::hw::mem_available)"
    testframework::assert_true "'${avail}' =~ ^[0-9]+$" "system::hw::mem_available returns MiB number"
}

# Test DMI getters (may be unavailable in containers — then must fail cleanly)
test_dmi_getters() {
    local value rc=0
    value="$(system::hw::product_name 2>/dev/null)" || rc=$?
    if [[ ${rc} -eq 0 ]]; then
        testframework::assert_true "-n \"${value}\"" "product_name returns a value when readable"
    else
        testframework::assert_equal "${E_ERROR}" "${rc}" "product_name fails cleanly without DMI access"
    fi
}

# Test graceful degradation for missing tools
test_missing_tool() {
    local rc=0
    system::hw::__require_tool definitely-not-a-real-tool-xyz some-package 2>/dev/null || rc=$?
    testframework::assert_equal "${E_ERROR}" "${rc}" "__require_tool fails for missing tool"

    rc=0
    system::hw::__require_tool bash 2>/dev/null || rc=$?
    testframework::assert_equal "${E_SUCCESS}" "${rc}" "__require_tool passes for present tool"
}

# Test argument validation
test_argument_validation() {
    local rc=0
    system::hw::disk_params "" 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "system::hw::disk_params rejects empty device"

    rc=0
    system::hw::disk_params "/dev/definitely-not-a-device" 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "system::hw::disk_params rejects non-block device"

    rc=0
    system::hw::badblocks_scan "" 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "system::hw::badblocks_scan rejects empty device"
}

# Test dry-run is honored by the scanner
test_dry_run() {
    export FRAMEWORK_DRY_RUN=true
    local rc=0
    system::hw::badblocks_scan /dev/null 2>/dev/null || rc=$?
    unset FRAMEWORK_DRY_RUN
    # /dev/null is not a block device, so validation fires first
    testframework::assert_equal "${E_INVALID}" "${rc}" "badblocks_scan validates device before dry-run"
}

# Test system::hw::summary never fails
test_summary_smoke() {
    local rc=0
    system::hw::summary >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "system::hw::summary exits 0 even without optional tools"
}

# Test system::hw::info prints help
test_info() {
    local out
    out="$(system::hw::info)"
    testframework::assert_true "'${out}' == *'system::hw::cpu'*" "system::hw::info lists commands"
}

main() {
    print_header "HW Unit Tests / Модульные тесты hw"

    testframework::init

    testframework::section "Module Loading / Загрузка модуля"
    test_module_loaded

    testframework::section "CPU and memory / CPU и память"
    test_cpu_functions

    testframework::section "DMI getters / DMI-геттеры"
    test_dmi_getters

    testframework::section "Tool checks / Проверки инструментов"
    test_missing_tool

    testframework::section "Argument validation / Валидация аргументов"
    test_argument_validation
    test_dry_run

    testframework::section "Smoke / Дымовые"
    test_summary_smoke
    test_info

    testframework::summary
}

main "$@"
