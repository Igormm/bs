#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsystemloggingunit.sh — Unit tests for lib/system/logging.sh
# tests/unit/testsystemloggingunit.sh — Модульные тесты для lib/system/logging.sh
#
# Only argument validation and clean() on a temp dir: nothing under /etc is touched.
# Только проверка аргументов и clean() во временном каталоге: /etc не трогается.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
load "lib/system/logging"

main() {
    print_header "System Logging Unit Tests / Модульные тесты system logging"
    testframework::init

    local rc tmp
    testframework::section "configure: level validation / проверка уровня"
    rc=0; system::logging::configure 'info/;x' >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "an unsafe level is rejected before any file is touched"

    testframework::section "clean / очистка"
    tmp="$(mktemp -d)"
    touch "${tmp}/old.log.1" "${tmp}/new.log.1" "${tmp}/keep.log"
    touch -d '40 days ago' "${tmp}/old.log.1" "${tmp}/keep.log"
    rc=0; system::logging::clean "${tmp}" "30; echo" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "a non-numeric age is rejected"
    testframework::assert_command "test -e '${tmp}/old.log.1'" "nothing is deleted on a rejected age"
    rc=0; system::logging::clean "${tmp}" 30 >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "clean succeeds"
    testframework::assert_command "test ! -e '${tmp}/old.log.1'" "an old rotated log is removed"
    testframework::assert_command "test -e '${tmp}/new.log.1' && test -e '${tmp}/keep.log'" "a fresh rotated log and the live log stay"
    rm -rf "${tmp}"

    testframework::summary
}

main "$@"
