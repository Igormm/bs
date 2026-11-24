#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testrunalltestsunit.sh — runalltests CLI: serial default, --jobs validation and env override
# tests/unit/testrunalltestsunit.sh — CLI runalltests: serial по умолчанию, проверка --jobs и env override

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly RUNNER="${BS_PROJECT_ROOT}/tests/runalltests.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

test_help_documents_jobs() {
    local out
    out="$(bash "${RUNNER}" --help)"
    testframework::assert_command "grep -q -- '--jobs N' <<< '${out}'" "help documents --jobs N"
    testframework::assert_command "grep -q 'BS_TEST_JOBS' <<< '${out}'" "help documents BS_TEST_JOBS"
}

test_invalid_jobs_are_refused() {
    local value rc
    for value in 0 -1 nope 1.5; do
        rc=0
        bash "${RUNNER}" --jobs "${value}" >/dev/null 2>&1 || rc=$?
        testframework::assert_equal "2" "${rc}" "--jobs ${value} is refused with exit 2"
    done
    rc=0
    bash "${RUNNER}" --jobs >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "2" "${rc}" "--jobs without a value is refused"
    rc=0
    BS_TEST_JOBS=0 bash "${RUNNER}" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "2" "${rc}" "BS_TEST_JOBS=0 is refused"
}

main() {
    testframework::section "Help / Справка"; test_help_documents_jobs
    testframework::section "Validation / Проверка"; test_invalid_jobs_are_refused
    testframework::summary
}

main "$@"
