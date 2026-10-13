#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testauditcoreerrorunit.sh — audit regressions for core/errorhandler
# tests/unit/testauditcoreerrorunit.sh — регрессии аудита для core/errorhandler
#   error::retry must never report success without running the command.
#   error::retry не должна возвращать успех, не запустив команду.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

test_retry_rejects_zero_attempts() {
    local rc=0 marker
    marker="$(mktemp)"
    rm -f "${marker}"
    error::retry 0 touch "${marker}" 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "retry 0 returns E_INVALID, not 0"
    testframework::assert_command "test ! -e '${marker}'" "retry 0 does not run the command"
}

test_retry_rejects_non_numeric() {
    local rc=0
    error::retry many true 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "retry with a non-numeric count returns E_INVALID"
}

test_retry_still_works() {
    local rc=0
    error::retry 1 true 2>/dev/null || rc=$?
    testframework::assert_equal "0" "${rc}" "retry 1 true succeeds"
    rc=0
    error::retry 1 false 2>/dev/null || rc=$?
    testframework::assert_equal "1" "${rc}" "retry 1 false returns the command status"
}

main() {
    print_header "Audit: core/errorhandler / Аудит: core/errorhandler"
    testframework::init
    testframework::section "error::retry"
    test_retry_rejects_zero_attempts
    test_retry_rejects_non_numeric
    test_retry_still_works
    testframework::summary
}

main "$@"
