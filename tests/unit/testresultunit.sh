#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testresultunit.sh — Unit tests for lib/integration/result
# tests/unit/testresultunit.sh — Модульные тесты для модуля result

set -euo pipefail

# Подключаем тестовый фреймворк / Source test framework
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Инициализируем BS / Initialize BS
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Подключаем тестируемый модуль / Load module under test
load "lib/io/files"
load "lib/integration/result"

main() {
    print_header "Integration Result Unit Tests"
    print_header "Модульные тесты результирующего модуля"

    testframework::init

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    # ==========================================
    # result::ok
    # ==========================================
    testframework::section "result::ok"

    local json
    json="$(result::ok "payload" "All good")"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.success == true'" "result::ok returns success=true"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.exit_code == 0'" "result::ok returns exit_code=0"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.data == \"payload\"'" "result::ok returns data payload"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.message == \"All good\"'" "result::ok returns message"

    # ==========================================
    # result::error
    # ==========================================
    testframework::section "result::error"

    local rc=0
    result::error 5 "Failed" > "${tmp_dir}/error.json" || rc=$?
    json="$(cat "${tmp_dir}/error.json")"
    testframework::assert_equal "5" "${rc}" "result::error preserves exit code"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.success == false'" "result::error returns success=false"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.exit_code == 5'" "result::error returns exit_code=5"

    # ==========================================
    # result::run successful command
    # ==========================================
    testframework::section "result::run success"

    json="$(result::run -- echo hello world)"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.success == true'" "run echo returns success=true"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.exit_code == 0'" "run echo returns exit_code=0"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.stdout == \"hello world\"'" "run echo captures stdout"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.operation == \"echo\"'" "run echo sets operation"
    testframework::assert_command "printf '%s' '${json}' | jq -e '(.args | length) == 3'" "run echo captures args"

    # ==========================================
    # result::run failing command
    # ==========================================
    testframework::section "result::run failure"

    rc=0
    result::run -- ls /nonexistent_path_12345 > "${tmp_dir}/run_error.json" || rc=$?
    json="$(cat "${tmp_dir}/run_error.json")"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.success == false'" "run failing command returns success=false"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.exit_code != 0'" "run failing command returns non-zero exit_code"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.stderr != \"\"'" "run failing command captures stderr"

    # ==========================================
    # result::wrap successful function
    # ==========================================
    testframework::section "result::wrap success"

    json="$(result::wrap io::files::exists /etc/passwd)"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.success == true'" "wrap exists returns success=true"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.exit_code == 0'" "wrap exists returns exit_code=0"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.operation == \"io::files::exists\"'" "wrap sets operation"

    # ==========================================
    # result::wrap failing function
    # ==========================================
    testframework::section "result::wrap failure"

    json="$(result::wrap io::files::exists /nonexistent_path_12345 || true)"
    testframework::assert_command "printf '%s' '${json}' | jq -e '.success == false'" "wrap failing function returns success=false"

    # ==========================================
    # result::write and BS_RESULT_FILE
    # ==========================================
    testframework::section "result::write / BS_RESULT_FILE"

    local result_file="${tmp_dir}/result.json"
    BS_RESULT_FILE="${result_file}" result::run -- echo "to file"
    testframework::assert_command "test -f '${result_file}'" "BS_RESULT_FILE creates file"
    testframework::assert_command "jq -e '.success == true' '${result_file}'" "BS_RESULT_FILE contains valid JSON"

    # ==========================================
    # result::get / result::is_success
    # ==========================================
    testframework::section "result::get / result::is_success"

    json="$(result::run -- true)"
    local parsed_rc
    result::get "${json}" "exit_code" parsed_rc
    testframework::assert_equal "0" "${parsed_rc}" "result::get parses exit_code"

    if result::is_success "${json}"; then
        testframework::assert_true "true" "result::is_success returns true for success"
    else
        testframework::assert_true "false" "result::is_success returns true for success"
    fi

    json="$(result::run -- false || true)"
    if result::is_success "${json}"; then
        testframework::assert_true "false" "result::is_success returns false for failure"
    else
        testframework::assert_true "true" "result::is_success returns false for failure"
    fi

    # ==========================================
    # Cleanup and summary
    # ==========================================
    rm -rf "${tmp_dir}"

    testframework::summary
}

main "$@"
