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

test_render_diff_noncontiguous() {
    TUI_COLS=10
    TUI_LINES=2
    tui::buf::clear
    tui::render >/dev/null
    # изменения в (0,0) и (0,5): несмежные, нужны два перепозиционирования
    # changes at (0,0) and (0,5): non-contiguous, both need a cursor jump
    tui::put 1 1 "X"
    tui::put 1 6 "Y"
    local out
    out="$(tui::render)"
    testframework::assert_command "printf '%s' '${out}' | grep -q $'\e\[1;1HX'" "render jumps to X at (0,0)"
    testframework::assert_command "printf '%s' '${out}' | grep -q $'\e\[1;6HY'" "render jumps to Y at (0,5)"
}

test_mouse_sgr() {
    tui::key_read < <(printf '\e[<0;23;5M')
    testframework::assert_equal "MOUSE" "${TUI_KEY}" "SGR mouse key"
    testframework::assert_equal "0" "${TUI_MOUSE_BUTTON}" "SGR mouse button"
    testframework::assert_equal "23" "${TUI_MOUSE_X}" "SGR mouse x"
    testframework::assert_equal "5" "${TUI_MOUSE_Y}" "SGR mouse y"
}

test_box_long_title() {
    TUI_COLS=20
    TUI_LINES=4
    tui::buf::clear
    # заголовок длиннее w-5: раньше str::repeat получал -10 и убивал shell
    # title longer than w-5: str::repeat used to get -10 and kill the shell
    tui::box 1 1 10 3 "long title here"
    testframework::assert_equal "╔" "${TUI_BUF[0,0]}" "box TL drawn with long title"
    testframework::assert_equal "╗" "${TUI_BUF[0,9]}" "box TR drawn with long title"
    testframework::assert_equal "═" "${TUI_BUF[0,1]}" "box top line continuous"
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

test_borders() {
    tui::border::set double
    testframework::assert_equal "╔" "${TUI_BORDER_TL}" "border double TL"
    testframework::assert_equal "╝" "${TUI_BORDER_BR}" "border double BR"

    tui::border::set rounded
    testframework::assert_equal "╭" "${TUI_BORDER_TL}" "border rounded TL"
    testframework::assert_equal "╯" "${TUI_BORDER_BR}" "border rounded BR"

    tui::border::set dashed
    testframework::assert_equal "┄" "${TUI_BORDER_H}" "border dashed horizontal"
    testframework::assert_equal "┆" "${TUI_BORDER_V}" "border dashed vertical"

    tui::border::set none
    # Без углов: угловые глифы = горизонтальная линия / no corners
    testframework::assert_equal "─" "${TUI_BORDER_TL}" "border none has no corner glyph"

    tui::border::set thick
    testframework::assert_equal "┏" "${TUI_BORDER_TL}" "border thick TL"

    testframework::assert_false "tui::border::set bogus" "border rejects unknown style"

    # Рамка с заголовком рисует непрерывную линию / box with title keeps line
    TUI_COLS=20
    TUI_LINES=4
    tui::buf::clear
    tui::border::set double
    tui::box 1 1 18 3 "T"
    testframework::assert_equal "╔" "${TUI_BUF[0,0]}" "box TL drawn"
    testframework::assert_equal "╗" "${TUI_BUF[0,17]}" "box TR drawn"
    testframework::assert_equal "═" "${TUI_BUF[0,1]}" "box top line continuous"
    testframework::assert_equal "T" "${TUI_BUF[0,3]}" "box title in line"
    testframework::assert_equal "╚" "${TUI_BUF[2,0]}" "box BL drawn"
    testframework::assert_equal "╝" "${TUI_BUF[2,17]}" "box BR drawn"
    testframework::assert_equal "║" "${TUI_BUF[1,0]}" "box side drawn"
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

    testframework::section "Diff render / Diff-рендер"
    test_render_diff_noncontiguous

    testframework::section "Mouse / Мышь"
    test_mouse_sgr

    testframework::section "Box / Рамка"
    test_box_long_title

    testframework::section "Modals / Модальные окна"
    test_modal_stack

    testframework::section "Borders / Рамки"
    test_borders

    testframework::summary
}

main "$@"