#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testcalcunit.sh — Unit tests for core/calc module
# tests/unit/testcalcunit.sh — Модульные тесты для модуля core/calc

set -euo pipefail

TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_SCRIPT_DIR
BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly BS_PROJECT_ROOT

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"
load "core/calc"

# calc::__autop adds p when the expression has no explicit print command
test_autop_adds_p() {
    local out
    out="$(calc::__autop '2 3 +')"
    testframework::assert_equal "2 3 + p" "${out}" "__autop adds p for plain expression"

    out="$(calc::__autop '10k 355 113 /')"
    testframework::assert_equal "10k 355 113 / p" "${out}" "__autop adds p for scale expression"
}

# calc::__autop preserves explicit print commands
test_autop_no_p_for_print_commands() {
    local out
    out="$(calc::__autop '2 3 + p')"
    testframework::assert_equal "2 3 + p" "${out}" "__autop keeps explicit p"

    out="$(calc::__autop '2 3 + n')"
    testframework::assert_equal "2 3 + n" "${out}" "__autop keeps n"

    out="$(calc::__autop '2 3 + P')"
    testframework::assert_equal "2 3 + P" "${out}" "__autop keeps P"

    out="$(calc::__autop '2 3 + f')"
    testframework::assert_equal "2 3 + f" "${out}" "__autop keeps f"
}

# calc::__autop does not add p for comments
test_autop_no_p_for_comments() {
    local out
    out="$(calc::__autop '# this is a comment')"
    testframework::assert_equal "# this is a comment" "${out}" "__autop does not add p for comment-only line"

    out="$(calc::__autop '2 3 + # inline comment')"
    testframework::assert_equal "2 3 + # inline comment" "${out}" "__autop keeps inline comment unchanged"
}

# calc::eval computes simple RPN expressions
test_eval_simple_rpn() {
    local out
    out="$(calc::eval '2 3 4 * +')"
    testframework::assert_equal "14" "${out}" "calc::eval computes 2 3 4 * +"

    out="$(calc::eval '6 2 /')"
    testframework::assert_equal "3" "${out}" "calc::eval computes 6 2 /"
}

# calc::eval honors explicit print commands
test_eval_honors_explicit_print() {
    local out
    out="$(calc::eval '2 3 + p')"
    testframework::assert_equal "5" "${out}" "calc::eval honors explicit p"

    out="$(calc::eval '2 3 + n')"
    testframework::assert_equal "5" "${out}" "calc::eval honors explicit n"
}

# calc::main --help exits 0 and prints help
test_main_help() {
    local out rc=0
    out="$(calc::main --help)" || rc=$?
    testframework::assert_true "$rc -eq 0" "calc::main --help exits 0"
    case "${out}" in
        *Usage*) testframework::assert_true "true" "calc::main --help prints usage" ;;
        *) testframework::assert_true "false" "calc::main --help prints usage" ;;
    esac
}

# calc::main handles missing dc or evaluates expression when dc is present
test_main_missing_dc_or_eval() {
    if is::command dc; then
        local out
        out="$(calc::main '2 3 +')"
        testframework::assert_equal "5" "${out}" "calc::main evaluates expression when dc is available"
    else
        local out rc=0
        out="$(calc::main '2 3 +' 2>&1)" || rc=$?
        testframework::assert_true "$rc -ne 0" "calc::main fails when dc is missing"
        case "${out}" in
            *dc*) testframework::assert_true "true" "calc::main reports dc missing" ;;
            *) testframework::assert_true "false" "calc::main reports dc missing" ;;
        esac
    fi
}

main() {
    print_header "Core Calc Unit Tests / Модульные тесты core/calc"

    testframework::init

    testframework::section "calc::__autop / Автопечать"
    test_autop_adds_p
    test_autop_no_p_for_print_commands
    test_autop_no_p_for_comments

    testframework::section "calc::eval / Вычисление"
    test_eval_simple_rpn
    test_eval_honors_explicit_print

    testframework::section "calc::main / Точка входа"
    test_main_help
    test_main_missing_dc_or_eval

    testframework::summary
}

main "$@"
