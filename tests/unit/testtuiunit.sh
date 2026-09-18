#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testtuiunit.sh — Unit tests for lib/tui/tui framework
# tests/unit/testtuiunit.sh — Модульные тесты TUI-фреймворка

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/tui/tui"

test_keys() {
    tui::key_read < <(printf '\e[A')
    testframework::assert_equal "UP" "${TUI_KEY}" "arrow up"

    tui::key_read < <(printf '\e[B')
    testframework::assert_equal "DOWN" "${TUI_KEY}" "arrow down"

    tui::key_read < <(printf '\e[5~')
    testframework::assert_equal "PGUP" "${TUI_KEY}" "page up"

    tui::key_read < <(printf '\e[3~')
    testframework::assert_equal "DELETE" "${TUI_KEY}" "delete key"

    tui::key_read < <(printf '\e[1;5C')
    testframework::assert_equal "CTRL+RIGHT" "${TUI_KEY}" "ctrl+right"

    tui::key_read < <(printf '\eOP')
    testframework::assert_equal "F1" "${TUI_KEY}" "f1"

    tui::key_read < <(printf '\e[24~')
    testframework::assert_equal "F12" "${TUI_KEY}" "f12"

    tui::key_read < <(printf '\e')
    testframework::assert_equal "ESC" "${TUI_KEY}" "escape"

    tui::key_read < <(printf '\n')
    testframework::assert_equal "ENTER" "${TUI_KEY}" "enter"

    tui::key_read < <(printf 'q')
    testframework::assert_equal "q" "${TUI_KEY}" "plain char"
    testframework::assert_equal "q" "${TUI_KEY_CHAR}" "plain char value"

    tui::key_read < <(printf '\eX')
    testframework::assert_equal "ALT+X" "${TUI_KEY}" "alt+char"
}

test_styles() {
    testframework::assert_equal $'\e[1;34m' "$(tui::style bold blue)" "style bold blue"

    TUI_TRUECOLOR=1
    testframework::assert_equal $'\e[1;44;38;2;255;136;0m' "$(tui::style bold bg_blue "#ff8800")" "style truecolor"
    TUI_TRUECOLOR=0
    testframework::assert_equal $'\e[7m' "$(tui::style reverse)" "style reverse"
    testframework::assert_equal "" "$(tui::style)" "style empty"
}

test_buffer() {
    TUI_COLS=20
    TUI_LINES=5
    tui::buf::clear
    tui::put 2 2 "hello" "$(tui::style green)"
    local key="1,1"
    testframework::assert_equal "h" "${TUI_BUF[${key}]}" "buffer stores char"
    testframework::assert_equal $'\e[32m' "${TUI_BUF_STYLE[${key}]}" "buffer stores style"

    local out
    out="$(tui::render | head -c 30)"
    testframework::assert_command "printf '%s' '${out}' | grep -q $'\e\[2;2H'" "render positions cursor"
}

test_modal_stack() {
    draw_a() { :; }
    draw_b() { :; }
    tui::modal::open a draw_a
    tui::modal::open b draw_b
    testframework::assert_equal "b" "$(tui::modal::top)" "top modal is b"
    tui::modal::close
    testframework::assert_equal "a" "$(tui::modal::top)" "close pops to a"
    tui::modal::close
    testframework::assert_equal "" "$(tui::modal::top)" "empty stack"
    testframework::assert_equal "0" "$?" "empty top returns 0"
}

main() {
    print_header "TUI Unit Tests / Модульные тесты TUI"

    testframework::init

    testframework::section "Keys / Клавиши"
    test_keys

    testframework::section "Styles / Стили"
    test_styles

    testframework::section "Buffer / Буфер"
    test_buffer

    testframework::section "Modals / Модальные окна"
    test_modal_stack

    testframework::summary
}

main "$@"