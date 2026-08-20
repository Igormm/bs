#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testscheduleunit.sh — Unit tests for lib/system/schedule module
# tests/unit/testscheduleunit.sh — Модульные тесты для модуля lib/system/schedule

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Test module loading
test_module_loaded() {
    load "lib/system/schedule"
    testframework::assert_true "${SYSTEM_SCHEDULE_LOADED:-}" "Module loaded"
}

# Test argument validation
test_argument_validation() {
    local rc=0
    system::schedule::at "" 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "at rejects empty time spec"

    rc=0
    system::schedule::at "now + 1 hour" 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "at rejects missing command"

    rc=0
    system::schedule::cron_add "" 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "cron_add rejects empty spec"

    rc=0
    system::schedule::cron_add "0 3 * * *" 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "cron_add rejects missing command"
}

# Test dry-run paths (no real at/crontab touched)
test_dry_run() {
    export FRAMEWORK_DRY_RUN=true

    local out
    out="$(system::schedule::at "now + 1 hour" echo hi 2>&1)"
    testframework::assert_true "'${out}' == *'DRY-RUN'*" "at honors dry-run"

    out="$(system::schedule::cron_add "0 3 * * *" /bin/true 2>&1)"
    testframework::assert_true "'${out}' == *'DRY-RUN'*" "cron_add honors dry-run"

    unset FRAMEWORK_DRY_RUN
}

# Test graceful degradation when tools are missing (or real behavior if present)
test_tool_degradation() {
    if ! utils::has crontab; then
        local rc=0
        system::schedule::cron_list 2>/dev/null || rc=$?
        testframework::assert_equal "${E_ERROR}" "${rc}" "cron_list fails cleanly without crontab"
    else
        local rc=0
        system::schedule::cron_list >/dev/null 2>&1 || rc=$?
        testframework::assert_equal "0" "${rc}" "cron_list works with crontab present"
    fi
}

main() {
    print_header "Schedule Unit Tests / Модульные тесты schedule"

    testframework::init

    testframework::section "Module Loading / Загрузка модуля"
    test_module_loaded

    testframework::section "Argument validation / Валидация аргументов"
    test_argument_validation

    testframework::section "Dry-run / Сухой прогон"
    test_dry_run

    testframework::section "Tool degradation / Деградация инструментов"
    test_tool_degradation

    testframework::summary
}

main "$@"
