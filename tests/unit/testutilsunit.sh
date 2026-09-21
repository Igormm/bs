#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testutilsunit.sh — Unit tests for core/utils module
# tests/unit/testutilsunit.sh — Модульные тесты для модуля core/utils

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Test utils::attempt ignores exit status
test_attempt_status() {
    if utils::attempt false; then
        testframework::assert_true "0 -eq 0" "utils::attempt returns 0 on failing command"
    else
        testframework::assert_true "1 -eq 2" "utils::attempt returns 0 on failing command"
    fi

    if utils::attempt true; then
        testframework::assert_true "0 -eq 0" "utils::attempt returns 0 on succeeding command"
    else
        testframework::assert_true "1 -eq 2" "utils::attempt returns 0 on succeeding command"
    fi
}

# Test utils::attempt keeps stdout but mutes stderr
test_attempt_streams() {
    local out
    out="$(utils::attempt printf 'visible')"
    testframework::assert_equal "visible" "${out}" "utils::attempt keeps stdout"

    out="$(utils::attempt bash -c 'printf noisy >&2; exit 3')"
    testframework::assert_equal "" "${out}" "utils::attempt mutes stderr of failing command"
}

# Test utils::attempt does not abort under set -e semantics
test_attempt_under_errexit() {
    (
        set -e
        utils::attempt false
        printf 'survived'
    ) > /tmp/bs_test_attempt.$$ 2>/dev/null || true
    local out
    out="$(cat /tmp/bs_test_attempt.$$ 2>/dev/null)"
    rm -f "/tmp/bs_test_attempt.$$"
    testframework::assert_equal "survived" "${out}" "utils::attempt survives set -e"
}

# Test time primitives return expected formats
test_time_primitives() {
    local s ms fl st ls
    s="$(utils::now_s)"
    testframework::assert_true "'${s}' =~ ^[0-9]+$" "utils::now_s returns epoch seconds"

    ms="$(utils::now_ms)"
    testframework::assert_true "'${ms}' =~ ^[0-9]+$" "utils::now_ms returns epoch milliseconds"
    testframework::assert_true "${#ms} -gt ${#s}" "utils::now_ms has more digits than now_s"

    fl="$(utils::now_float)"
    testframework::assert_true "'${fl}' =~ ^[0-9]+\.[0-9]+$" "utils::now_float returns seconds with fraction"

    st="$(utils::stamp)"
    testframework::assert_true "'${st}' =~ ^[0-9]{8}_[0-9]{6}$" "utils::stamp returns YYYYMMDD_HHMMSS"

    ls="$(utils::log_stamp)"
    testframework::assert_true "'${ls}' =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$" "utils::log_stamp returns YYYY-MM-DD HH:MM:SS"
}

main() {
    print_header "Core Utils Unit Tests / Модульные тесты core/utils"

    testframework::init

    testframework::section "utils::attempt / Игнорирование статуса"
    test_attempt_status
    test_attempt_streams
    test_attempt_under_errexit

    testframework::section "Time primitives / Примитивы времени"
    test_time_primitives

    testframework::section "Wrappers / Обёртки"
    test_tempfile
    test_human_size
    test_head_bytes

    testframework::summary
}


# Test utils::tempfile creates and cleans up
test_tempfile() {
    local t1 t2
    t1="$(utils::tempfile)"
    testframework::assert_true "-e '${t1}'" "utils::tempfile creates a file"
    t2="$(utils::tempfile --dir)"
    testframework::assert_true "-d '${t2}'" "utils::tempfile --dir creates a directory"

    utils::__tmp_cleanup
    testframework::assert_true "! -e '${t1}'" "utils::__tmp_cleanup removes files"
    testframework::assert_true "! -e '${t2}'" "utils::__tmp_cleanup removes directories"
}

# Test utils::human_size normalization
test_human_size() {
    testframework::assert_equal "15.5 GiB" "$(utils::human_size 16626573312)" "human_size bytes"
    testframework::assert_equal "12.0 MiB" "$(utils::human_size 12288K)" "human_size suffixed"
    testframework::assert_equal "1.0 KiB" "$(utils::human_size 1024)" "human_size exact KiB"
    testframework::assert_equal "abc" "$(utils::human_size abc)" "human_size passes through unparseable"
}

# Test utils::head_bytes capped read
test_head_bytes() {
    local tmp
    tmp="$(utils::tempfile)"
    printf 'hello world
' > "${tmp}"
    testframework::assert_equal "hello" "$(utils::head_bytes "${tmp}" 5)" "head_bytes caps read"
    testframework::assert_equal "hello world" "$(utils::head_bytes "${tmp}")" "head_bytes default 4000"
    testframework::assert_false "utils::head_bytes /no/such 5" "head_bytes rejects missing file"
    utils::__tmp_cleanup
}

main "$@"
