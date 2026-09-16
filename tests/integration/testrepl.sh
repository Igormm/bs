#!/usr/bin/env bs
# shellcheck shell=bash
# tests/integration/testrepl.sh — Integration tests for `bs repl`
# tests/integration/testrepl.sh — Интеграционные тесты REPL
#
# Безопасный прогон: история и конфиг REPL изолируются через XDG_CONFIG_HOME
# во временный каталог — реальный ~/.config не трогается.
# Safe run: REPL history/config are isolated via XDG_CONFIG_HOME in a temp
# dir — the real ~/.config is never touched.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly BS_LAUNCHER="${BS_PROJECT_ROOT}/bs"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

readonly TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bs_repl_test.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

# Запуск REPL: stdin — команды, XDG_CONFIG_HOME изолирован
# Run REPL: stdin is the commands, XDG_CONFIG_HOME is isolated
run_repl() {
    local input="$1"
    local xdg="${TMP_ROOT}/xdg.$$"
    printf '%s\n' "${input}" | env XDG_CONFIG_HOME="${xdg}" bash "${BS_LAUNCHER}" repl 2>&1
}

test_repl_help_flag() {
    local out rc=0
    out="$(bash "${BS_LAUNCHER}" repl --help 2>&1)" || rc=$?
    testframework::assert_equal "0" "${rc}" "bs repl --help exits 0"
    testframework::assert_true "'${out}' =~ bs\ repl" "help mentions usage"
}

test_repl_banner() {
    local out
    out="$(run_repl ':exit')"
    testframework::assert_true "'${out}' =~ BS\ REPL" "banner is printed"
}

test_repl_eval_success() {
    local out
    out="$(run_repl 'is::dir /etc && echo DIR_OK
:exit')"
    testframework::assert_true "'${out}' =~ DIR_OK" "core predicate is evaluated"
}

test_repl_eval_failure_reports_rc() {
    local out
    out="$(run_repl 'false
:exit')"
    testframework::assert_true "'${out}' =~ expression\ failed\ \(rc=1\)" "failed expression reports rc=1"
}

test_repl_survives_bad_input() {
    local out
    out="$(run_repl 'printf "%s\n" "$UNDEFINED_REPL_VAR"
echo SURVIVED
:exit')"
    testframework::assert_true "'${out}' =~ SURVIVED" "unbound variable does not kill the loop"
}

test_repl_load_module() {
    local out
    out="$(run_repl ':load lib/io/streams
declare -F io::streams::print >/dev/null && echo STREAMS_LOADED
:exit')"
    testframework::assert_true "'${out}' =~ loaded:\ lib/io/streams" ":load reports success"
    testframework::assert_true "'${out}' =~ STREAMS_LOADED" "module functions become available"
}

test_repl_list() {
    local out
    out="$(run_repl ':list
:exit')"
    testframework::assert_true "'${out}' =~ core/utils\.sh" ":list shows core modules"
    testframework::assert_true "'${out}' =~ lib/system/hw\.sh" ":list shows lib modules"
}

test_repl_doc() {
    local out
    out="$(run_repl ':doc is::file
:exit')"
    testframework::assert_true "'${out}' =~ is::file\ \(\)" ":doc prints function source"
}

test_repl_info() {
    local out
    out="$(run_repl ':info lib/system/hw
:exit')"
    testframework::assert_true "'${out}' =~ Hardware\ information" ":info prints module header"
}

test_repl_state_persists() {
    local out
    out="$(run_repl 'x=42
printf "GOT=%s\n" "$x"
:exit')"
    testframework::assert_true "'${out}' =~ GOT=42" "variables persist between lines"
}

test_repl_multiline_continuation() {
    local out count_a=1 count_b=1
    out="$(run_repl 'printf "A\
b"
:exit')"
    printf '%s\n' "${out}" | grep -qx 'A' || count_a=0
    testframework::assert_equal "1" "${count_a}" "first continuation line evaluated"
    printf '%s\n' "${out}" | grep -qx 'b' || count_b=0
    testframework::assert_equal "1" "${count_b}" "second continuation line concatenated"
}

test_repl_history_persisted() {
    local xdg="${TMP_ROOT}/xdg_hist.$$"
    printf 'echo HIST_ONE\necho HIST_TWO\n:exit\n' | \
        env XDG_CONFIG_HOME="${xdg}" bash "${BS_LAUNCHER}" repl >/dev/null 2>&1 || true

    local hist_file="${xdg}/bs/repl_history"
    if [[ -f "${hist_file}" ]] && grep -q 'HIST_ONE' "${hist_file}" && grep -q 'HIST_TWO' "${hist_file}"; then
        testframework::assert_true "true" "history saved to XDG_CONFIG_HOME"
    else
        testframework::assert_true "false" "history saved to XDG_CONFIG_HOME"
    fi

    local out
    out="$(printf ':hist\n:exit\n' | env XDG_CONFIG_HOME="${xdg}" bash "${BS_LAUNCHER}" repl 2>&1)"
    testframework::assert_true "'${out}' =~ HIST_ONE" "previous session history is loaded"
}

test_repl_rerun_history() {
    local out
    out="$(run_repl 'echo HITME
:!1
:exit')"
    testframework::assert_true "'${out}' =~ HITME" ":!N re-runs history entry"
}

main() {
    print_header "bs repl Integration Tests / Интеграционные тесты bs repl"

    testframework::init

    testframework::section "Basics / Основы"
    test_repl_help_flag
    test_repl_banner
    test_repl_eval_success
    test_repl_eval_failure_reports_rc
    test_repl_survives_bad_input

    testframework::section "Module workflow / Модули"
    test_repl_load_module
    test_repl_list
    test_repl_doc
    test_repl_info

    testframework::section "State, continuation, history / Состояние и история"
    test_repl_state_persists
    test_repl_multiline_continuation
    test_repl_history_persisted
    test_repl_rerun_history

    testframework::summary
}

main "$@"