#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testconfirmunit.sh — Unit tests for lib/ui/elements/confirm.sh
# tests/unit/testconfirmunit.sh — Модульные тесты для модуля lib/ui/elements/confirm.sh

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/ui/elements/confirm"

# Build a left-to-right string of the requested buffer row (0-based).
_buf_row() {
    local -i r="$1" c
    local line=""
    for (( c = 0; c < TUI_COLS; c++ )); do
        line+="${TUI_BUF["${r},${c}"]:- }"
    done
    printf '%s' "${line}"
}

# Render a confirm dialog, feeding stdin through to mimic interactive input.
_run_confirm() {
    tui::buf::clear
    ui::elements::confirm::draw "$@"
    tui::render >/dev/null
}

# Default test terminal size is 80x24; confirm::draw uses w=56, h=8.
# Yes option sits at row 12 (1-based), col 16 → buffer key "11,15".
# No option sits at row 12, col 28 → buffer key "11,27".
_confirm_yes_style() {
    printf '%s' "${TUI_BUF_STYLE["11,15"]:-}"
}

_confirm_no_style() {
    printf '%s' "${TUI_BUF_STYLE["11,27"]:-}"
}

test_confirm_returns_zero_and_prints_question() {
    local rc=0
    ( _run_confirm "Confirm / Подтверждение" "Delete the task?" 0 ) >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -eq 0" "confirm draw exits 0"

    tui::buf::clear
    ui::elements::confirm::draw "Confirm / Подтверждение" "Delete the task?" 0 >/dev/null

    local row
    row="$(_buf_row 9)"
    testframework::assert_command "printf '%s' '${row}' | grep -Fq 'Delete the task'" "buffer row contains the question"
}

test_confirm_yes_input() {
    local rc=0
    ( _run_confirm "Confirm" "Continue?" 0 ) <<< "y" >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -eq 0" "confirm with y input exits 0"

    tui::buf::clear
    ui::elements::confirm::draw "Confirm" "Continue?" 0 >/dev/null

    local row
    row="$(_buf_row 9)"
    testframework::assert_command "printf '%s' '${row}' | grep -Fq 'Continue'" "confirm with y input draws the question"
}

test_confirm_no_input() {
    local rc=0
    ( _run_confirm "Confirm" "Abort?" 1 ) <<< "n" >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -eq 0" "confirm with n input exits 0"

    tui::buf::clear
    ui::elements::confirm::draw "Confirm" "Abort?" 1 >/dev/null

    local row
    row="$(_buf_row 11)"
    testframework::assert_command "printf '%s' '${row}' | grep -Fq '[ Нет / No ]'" "confirm with n input shows No option"
}

test_confirm_default_answer_highlights_yes() {
    tui::buf::clear
    ui::elements::confirm::draw "Confirm" "Use default?" >/dev/null

    local yes_style no_style
    yes_style="$(_confirm_yes_style)"
    no_style="$(_confirm_no_style)"

    if [[ -n "${yes_style}" ]]; then
        testframework::assert_true "true" "default answer highlights Yes / Да"
    else
        testframework::assert_true "false" "default answer highlights Yes / Да"
    fi

    if [[ -z "${no_style}" ]]; then
        testframework::assert_true "true" "default answer does not highlight No / Нет"
    else
        testframework::assert_true "false" "default answer does not highlight No / Нет"
    fi
}

main() {
    print_header "UI Confirm Element Unit Tests / Модульные тесты элемента confirm"

    testframework::init

    testframework::section "Question rendering / Отрисовка вопроса"
    test_confirm_returns_zero_and_prints_question

    testframework::section "Interactive input / Интерактивный ввод"
    test_confirm_yes_input
    test_confirm_no_input

    testframework::section "Default answer / Ответ по умолчанию"
    test_confirm_default_answer_highlights_yes

    testframework::summary
}

main "$@"
