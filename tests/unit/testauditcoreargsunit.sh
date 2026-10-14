#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testauditcoreargsunit.sh — audit regressions for core/args
# tests/unit/testauditcoreargsunit.sh — регрессии аудита для core/args
#   "-h" after "--" or as the value of a value flag is data, not a help request.
#   "-h" после "--" или как значение флага — это данные, а не запрос справки.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"
load "core/args"

setup_tree() {
    args::reset
    args::level 1 run stop
    args::flag pattern value ""
    args::flag verbose bool
}

test_dash_h_after_separator_is_raw() {
    setup_tree
    local rc=0
    args::parse run -- -h || rc=$?
    testframework::assert_equal "0" "${rc}" "parse succeeds"
    testframework::assert_equal "0" "${ARGS_HELP_REQUESTED}" "-h after -- is not a help request"
    testframework::assert_equal "-h" "${ARGS_REST[*]:-}" "-h after -- lands in ARGS_REST"
}

test_dash_h_as_flag_value() {
    setup_tree
    local rc=0
    args::parse run --pattern -h || rc=$?
    testframework::assert_equal "0" "${rc}" "parse succeeds"
    testframework::assert_equal "0" "${ARGS_HELP_REQUESTED}" "-h as a flag value is not a help request"
    testframework::assert_equal "-h" "${ARGS_FLAGS[pattern]:-}" "-h is stored as the flag value"
}

test_real_help_still_works() {
    setup_tree
    local out
    out="$(args::parse run -h 2>&1)"
    testframework::assert_true "'${out}' == *Usage*" "plain -h still prints help"
    out="$(args::parse --pattern x --help 2>&1)"
    testframework::assert_true "'${out}' == *Usage*" "--help after a flag with its value still prints help"
}

main() {
    print_header "Audit: core/args / Аудит: core/args"
    testframework::init
    testframework::section "Help scan / Поиск запроса справки"
    test_dash_h_after_separator_is_raw
    test_dash_h_as_flag_value
    test_real_help_still_works
    testframework::summary
}

main "$@"
