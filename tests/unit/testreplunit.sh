#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testreplunit.sh — Unit tests for core/repl module
# tests/unit/testreplunit.sh — Модульные тесты для модуля core/repl

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"
load "core/repl"

# Isolated temporary directory for REPL history file tests.
readonly REPL_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bs_repl_unit.XXXXXX")"
trap 'rm -rf "${REPL_TMP_ROOT}"' EXIT

test_repl_help() {
    local out
    out="$(repl::help)"
    testframework::assert_true "'${out}' =~ :load" "repl::help mentions :load"
    testframework::assert_true "'${out}' =~ :list" "repl::help mentions :list"
    testframework::assert_true "'${out}' =~ :doc" "repl::help mentions :doc"
    testframework::assert_true "'${out}' =~ :info" "repl::help mentions :info"
    testframework::assert_true "'${out}' =~ :exit" "repl::help mentions :exit"
}

test_repl_history_file() {
    local default out

    default="${XDG_CONFIG_HOME:-${HOME}/.config}/bs/repl_history"
    out="$(repl::__history_file)"
    testframework::assert_equal "${default}" "${out}" "repl::__history_file returns default path"

    local override="${REPL_TMP_ROOT}/custom_history"
    export BS_REPL_HISTORY_FILE="${override}"
    out="$(repl::__history_file)"
    testframework::assert_equal "${override}" "${out}" "repl::__history_file respects BS_REPL_HISTORY_FILE"
    unset BS_REPL_HISTORY_FILE
}

test_repl_history_add_save_load() {
    local hist_file="${REPL_TMP_ROOT}/history_test"
    REPL_HISTORY=()

    repl::__history_add "first line"
    repl::__history_add "second line"
    testframework::assert_equal "2" "${#REPL_HISTORY[@]}" "history add appends lines"

    export BS_REPL_HISTORY_FILE="${hist_file}"
    repl::__history_save
    testframework::assert_true "-f '${hist_file}'" "history save creates file"

    REPL_HISTORY=()
    repl::__history_load "${hist_file}"
    testframework::assert_equal "2" "${#REPL_HISTORY[@]}" "history load restores entries"
    testframework::assert_equal "first line" "${REPL_HISTORY[0]}" "history load preserves first entry"
    testframework::assert_equal "second line" "${REPL_HISTORY[1]}" "history load preserves second entry"

    unset BS_REPL_HISTORY_FILE
    REPL_HISTORY=()
}

test_repl_history_add_skips_empty() {
    REPL_HISTORY=()
    repl::__history_add ""
    testframework::assert_equal "0" "${#REPL_HISTORY[@]}" "history add ignores empty line"
}

test_repl_command_help() {
    local out
    out="$(repl::__command :help)"
    testframework::assert_true "'${out}' =~ REPL\ commands" "repl::__command :help prints help"
}

test_repl_command_version() {
    local out
    out="$(repl::__command :version)"
    testframework::assert_true "'${out}' =~ ${BS_VERSION:-}" "repl::__command :version prints version"
}

test_repl_command_list() {
    local out
    out="$(repl::__command :list)"
    testframework::assert_true "'${out}' =~ core/utils\.sh" "repl::__command :list shows core modules"
    testframework::assert_true "'${out}' =~ lib/io/streams\.sh" "repl::__command :list shows lib modules"
}

test_repl_command_load() {
    local out
    out="$(repl::__command ':load lib/io/streams')"
    testframework::assert_true "'${out}' =~ loaded:\ lib/io/streams" "repl::__command :load reports success"
}

test_repl_command_doc() {
    local out
    out="$(repl::__command ':doc bs::version::print')"
    if [[ "${out}" =~ bs::version::print[[:space:]]*\(\) ]]; then
        testframework::assert_true "true" "repl::__command :doc prints function source"
    else
        testframework::assert_true "false" "repl::__command :doc prints function source"
    fi
}

test_repl_command_info() {
    local out
    out="$(repl::__command ':info core/logger')"
    testframework::assert_true "'${out}' =~ core/logger\.sh" "repl::__command :info prints module header"
}

test_repl_command_exit() {
    local rc=0
    repl::__command :q || rc=$?
    testframework::assert_equal "1" "${rc}" "repl::__command :q returns exit request"
}

test_repl_eval() {
    local out rc=0
    out="$(repl::__eval 'printf OK')" || rc=$?
    testframework::assert_equal "0" "${rc}" "repl::__eval returns 0"
    testframework::assert_equal "OK" "${out}" "repl::__eval captures stdout"

    rc=0
    out="$(repl::__eval 'false' 2>&1)" || rc=$?
    testframework::assert_equal "0" "${rc}" "repl::__eval always returns 0 even on failure"
    if [[ "${out}" =~ expression[[:space:]]+failed[[:space:]]*\(rc=1\) ]]; then
        testframework::assert_true "true" "repl::__eval reports failure rc"
    else
        testframework::assert_true "false" "repl::__eval reports failure rc"
    fi
}

main() {
    print_header "Core REPL Unit Tests / Модульные тесты core/repl"

    testframework::init

    testframework::section "Help / Справка"
    test_repl_help

    testframework::section "History / История"
    test_repl_history_file
    test_repl_history_add_save_load
    test_repl_history_add_skips_empty

    testframework::section "REPL commands / Команды REPL"
    test_repl_command_help
    test_repl_command_version
    test_repl_command_list
    test_repl_command_load
    test_repl_command_doc
    test_repl_command_info
    test_repl_command_exit

    testframework::section "Evaluation / Выполнение"
    test_repl_eval

    testframework::summary
}

main "$@"
