#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testbsunit.sh — Unit tests for bootstrap/bs.sh (pre-kernel namespace)
# tests/unit/testbsunit.sh — Модульные тесты bootstrap/bs.sh (pre-kernel namespace)
#
# Тестирует bs::shell::*, bs::script_dir, bs::append_local_bin_to_path и guard.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Test raw self-guard: double source is a no-op, functions stay defined
test_guard() {
    local result
    if source "${BS_PROJECT_ROOT}/bootstrap/bs.sh"; then
        result=0
    else
        result=1
    fi
    testframework::assert_true "${result} -eq 0" "bs.sh double source is a no-op"
    testframework::assert_command "declare -F bs::shell::name" "functions survive double source"
    testframework::assert_true "-n \"${__BS_SH_SOURCED:-}\"" "guard flag __BS_SH_SOURCED is set"
}

# Test PATH tweak is idempotent / PATH-твик идемпотентен
test_append_local_bin_to_path() {
    local path_after
    path_after="$(PATH="/usr/bin:/bin" bs::append_local_bin_to_path; printf '%s' "${PATH}")"
    testframework::assert_true "'${path_after}' =~ ^${HOME}/\.local/bin:" "~/.local/bin is prepended once"
}

# Test shell capability helpers / Хелперы оболочки как capability
test_shell_helpers() {
    testframework::assert_equal "bash" "$(bs::shell::name)" "shell name is bash under bash"
    testframework::assert_equal "1" "$(bs::shell::ok)" "bash 4+ is shell_ok"
    testframework::assert_true "'$(bs::shell::version)' =~ ^[0-9]+$" "shell version is numeric"
    # is_sourced: этот тест-файл исполняется (не source'ится) → NOT sourced
    bs::shell::is_sourced && testframework::fail "test file executed directly must not be sourced" || testframework::assert_true "0 -eq 0" "executed file is not sourced"
}

# Test the shell version gate / Гейт версии оболочки
test_ensure_version() {
    local result

    if bs::shell::ensure_version 4; then
        result=0
    else
        result=1
    fi
    testframework::assert_true "${result} -eq 0" "ensure_version 4 passes"

    if bs::shell::ensure_version; then
        result=0
    else
        result=1
    fi
    testframework::assert_true "${result} -eq 0" "ensure_version defaults to 4"

    local err
    err="$(bs::shell::ensure_version 99 2>&1 || true)"
    testframework::assert_true "'${err}' =~ ERROR" "ensure_version prints ERROR to stderr on failure"

    if bs::shell::ensure_version 99 2>/dev/null; then
        result=0
    else
        result=1
    fi
    testframework::assert_true "${result} -eq 1" "ensure_version returns 1 for an impossible version"

    local bad_err
    bad_err="$(bs::shell::ensure_version foo 2>&1 || true)"
    testframework::assert_true "'${bad_err}' =~ ERROR" "ensure_version rejects a non-numeric version"
}

# Test bs::script_dir resolves the caller's directory
test_script_dir() {
    local dir
    dir="$(bs::script_dir)"
    local expected
    expected="$(cd -- "${TEST_SCRIPT_DIR}" >/dev/null 2>&1 && pwd -P)"
    testframework::assert_equal "${expected}" "${dir}" "bs::script_dir returns caller directory"

    # Invalid index should fail
    if bs::script_dir 99 >/dev/null 2>&1; then
        testframework::assert_true "1 -eq 2" "bs::script_dir fails on invalid index"
    else
        testframework::assert_true "0 -eq 0" "bs::script_dir fails on invalid index"
    fi
}

main() {
    print_header "Bootstrap bs.sh Unit Tests / Модульные тесты pre-kernel namespace"

    testframework::init

    # Load bs.sh directly to ensure we test the raw entry point
    source "${BS_PROJECT_ROOT}/bootstrap/bs.sh"

    testframework::section "Guard / Защита от повторной загрузки"
    test_guard

    testframework::section "PATH Tweak / Твик PATH"
    test_append_local_bin_to_path

    testframework::section "Shell / Оболочка"
    test_shell_helpers

    testframework::section "Shell Version Gate / Гейт версии оболочки"
    test_ensure_version

    testframework::section "Script Dir / Каталог скрипта"
    test_script_dir

    testframework::summary
}

main "$@"