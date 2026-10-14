#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsystemauditreportunit.sh — systemaudit text report under strict mode
# tests/unit/testsystemauditreportunit.sh — текстовый отчёт systemaudit в строгом режиме
#
# Regression: counters started at 0 and were increased with ((x++)), which
# returns status 1 for 0 and stopped the whole script under `set -e`.
# Регрессия: счётчики стартовали с 0 и росли через ((x++)), что даёт код 1
# для 0 и останавливало весь скрипт под `set -e`.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"
# The module creates ~/.config/systemaudit: use a throw-away HOME
# Модуль создаёт ~/.config/systemaudit: используем одноразовый HOME
TEST_HOME="$(mktemp -d)"
export HOME="${TEST_HOME}"
load "lib/audit/systemaudit"

main() {
    print_header "Systemaudit Report Unit Tests / Тесты отчёта systemaudit"
    testframework::init

    local report="${TEST_HOME}/report.txt" rc=0
    AUDIT_FINDINGS=(
        '{"severity": "CRITICAL", "title": "t1", "category": "c", "description": "d", "recommendation": "r", "timestamp": "x"}'
        '{"severity": "INFO", "title": "t2", "category": "c", "description": "d", "recommendation": "r", "timestamp": "x"}'
    )
    AUDIT_SCORE=50
    AUDIT_SUMMARY="test"

    testframework::section "text report / текстовый отчёт"
    systemaudit::generate_text_report "${report}" || rc=$?
    testframework::assert_equal "0" "${rc}" "report generation does not stop under set -e"
    testframework::assert_command "grep -q 'Critical: 1' '${report}'" "critical counter counted from 0"
    testframework::assert_command "grep -q 'Info: 1' '${report}'" "info counter counted from 0"
    testframework::assert_command "grep -q 'Finding 2:' '${report}'" "all findings are listed"

    rm -rf "${TEST_HOME}"
    testframework::summary
}

main "$@"
