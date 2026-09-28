#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testappunit.sh — Unit tests for lib/tui/app high-level layer
# tests/unit/testappunit.sh — Модульные тесты высокоуровневого слоя lib/tui/app

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/tui/app"

declare -g TEST_FIRED=""
declare -g TEST_ARGS=""

test_cb() {
    TEST_FIRED="yes"
}

test_cb_with_arg() {
    TEST_ARGS="${1}"
}

test_register() {
    tui::app::reset
    tui::app::window main "Hello" 2 2 30 9
    testframework::assert_true '-n "${TUI_APP_WINDOWS[main]:-}"' "window registered"
    testframework::assert_equal "Hello" "${TUI_APP_WINDOWS[main]%%$'\t'*}" "window title stored"

    tui::app::button main greet "Say hello" 3 4
    testframework::assert_true '-n "${TUI_APP_BUTTONS[greet]:-}"' "button registered"
    testframework::assert_equal "greet" "${TUI_APP_FOCUS_ORDER[0]}" "button in focus order"

    tui::app::on greet test_cb
    testframework::assert_equal "test_cb" "${TUI_APP_CALLBACKS[greet]}" "button callback stored"

    tui::app::bind "q|Q" test_cb
    testframework::assert_equal "test_cb" "${TUI_APP_BINDINGS[q]}" "binding stored (q)"
    testframework::assert_equal "test_cb" "${TUI_APP_BINDINGS[Q]}" "binding stored (Q)"

    tui::app::bind "UP" test_cb_with_arg up
    testframework::assert_true '"${TUI_APP_BINDINGS[UP]}" == test_cb_with_arg*$'"'"'\t'"'"'up' "binding stores args"

    tui::app::focus greet
    testframework::assert_equal "greet" "${TUI_APP_FOCUS}" "initial focus set"

    tui::app::statusbar "hello"
    testframework::assert_equal "hello" "${TUI_APP_STATUS}" "statusbar text stored"
}

test_focus_navigation() {
    tui::app::reset
    tui::app::window main "Hello" 2 2 30 9
    tui::app::button main one "One" 3 4
    tui::app::button main two "Two" 5 4
    tui::app::button main three "Three" 7 4
    tui::app::focus one

    tui::app::key TAB
    testframework::assert_equal "two" "${TUI_APP_FOCUS}" "TAB moves to next button"

    tui::app::key DOWN
    testframework::assert_equal "three" "${TUI_APP_FOCUS}" "DOWN moves to next button"

    tui::app::key TAB
    testframework::assert_equal "one" "${TUI_APP_FOCUS}" "TAB wraps around"

    tui::app::key UP
    testframework::assert_equal "three" "${TUI_APP_FOCUS}" "UP moves to previous button"

    tui::app::key LEFT
    testframework::assert_equal "two" "${TUI_APP_FOCUS}" "LEFT moves to previous button"
}

test_button_press() {
    tui::app::reset
    tui::app::window main "Hello" 2 2 30 9
    tui::app::button main greet "Say hello" 3 4
    tui::app::on greet test_cb
    tui::app::focus greet

    TEST_FIRED=""
    tui::app::key ENTER
    testframework::assert_equal "yes" "${TEST_FIRED}" "ENTER presses the focused button"
}

test_bind_precedence() {
    tui::app::reset
    tui::app::window main "Hello" 2 2 30 9
    tui::app::button main quit "Quit" 3 4
    tui::app::on quit test_cb

    TEST_FIRED=""
    tui::app::bind "q" test_cb
    tui::app::key q
    testframework::assert_equal "yes" "${TEST_FIRED}" "explicit binding wins over default quit"

    TEST_FIRED=""
    tui::app::bind "ENTER" test_cb
    tui::app::key ENTER
    testframework::assert_equal "yes" "${TEST_FIRED}" "explicit ENTER binding wins over button press"

    tui::app::key q
    testframework::assert_equal "0" "${TUI_APP_STOP}" "bound q does not quit the app"
}

test_binding_args() {
    tui::app::reset
    tui::app::bind "UP" test_cb_with_arg up

    TEST_ARGS=""
    tui::app::key UP
    testframework::assert_equal "up" "${TEST_ARGS}" "binding passes extra args to the callback"
}

test_input_modal() {
    tui::app::reset
    tui::app::input_modal "Add task" test_cb_with_arg test_cb

    tui::app::key h
    tui::app::key e
    tui::app::key l
    tui::app::key l
    tui::app::key o
    testframework::assert_equal "hello" "${TUI_APP_INPUT}" "typed chars accumulate"

    tui::app::key BACKSPACE
    testframework::assert_equal "hell" "${TUI_APP_INPUT}" "BACKSPACE removes a char"

    tui::app::key a
    tui::app::key LEFT
    tui::app::key X
    testframework::assert_equal "hellXa" "${TUI_APP_INPUT}" "insert at cursor position"

    tui::app::key RIGHT
    tui::app::key Y
    testframework::assert_equal "hellXaY" "${TUI_APP_INPUT}" "insert after cursor"

    TEST_ARGS=""
    tui::app::key ENTER
    testframework::assert_equal "hellXaY" "${TEST_ARGS}" "ENTER submits the text"
    testframework::assert_equal "" "${TUI_APP_MODAL}" "input modal closed after submit"

    tui::app::input_modal "Add task" test_cb_with_arg test_cb
    TEST_FIRED=""
    tui::app::key ESC
    testframework::assert_equal "yes" "${TEST_FIRED}" "ESC runs the cancel callback"
    testframework::assert_equal "" "${TUI_APP_MODAL}" "input modal closed after cancel"
}

test_input_modal_prefill() {
    tui::app::reset
    tui::app::input_modal "Edit task" test_cb_with_arg "" "old text"

    testframework::assert_equal "old text" "${TUI_APP_INPUT}" "prefill text loaded"
    testframework::assert_equal "8" "${TUI_APP_INPUT_CURSOR}" "cursor at end of prefill"
}

test_confirm_modal() {
    tui::app::reset
    tui::app::confirm_modal "Delete task" "task text" test_cb test_cb

    TEST_FIRED=""
    tui::app::key y
    testframework::assert_equal "yes" "${TEST_FIRED}" "y activates Yes"
    testframework::assert_equal "" "${TUI_APP_MODAL}" "confirm modal closed after yes"

    tui::app::confirm_modal "Delete task" "task text" test_cb test_cb
    TEST_FIRED=""
    tui::app::key n
    testframework::assert_equal "yes" "${TEST_FIRED}" "n activates No (cancel callback)"
    testframework::assert_equal "" "${TUI_APP_MODAL}" "confirm modal closed after no"

    tui::app::confirm_modal "Delete task" "task text" test_cb test_cb
    tui::app::key LEFT
    testframework::assert_equal "1" "${TUI_APP_CONFIRM_SEL}" "LEFT switches to No"
    tui::app::key RIGHT
    testframework::assert_equal "0" "${TUI_APP_CONFIRM_SEL}" "RIGHT switches to Yes"

    TEST_FIRED=""
    tui::app::key ENTER
    testframework::assert_equal "yes" "${TEST_FIRED}" "ENTER activates the selected option"

    tui::app::confirm_modal "Delete task" "task text" test_cb test_cb
    tui::app::key ESC
    testframework::assert_equal "yes" "${TEST_FIRED}" "ESC cancels"
}

test_message_modal() {
    tui::app::reset
    tui::app::message_modal "Hello" "message text" test_cb

    TEST_FIRED=""
    tui::app::key ENTER
    testframework::assert_equal "yes" "${TEST_FIRED}" "ENTER closes the message and runs the close callback"
    testframework::assert_equal "" "${TUI_APP_MODAL}" "message modal closed"

    tui::app::message_modal "Hello" "message text"
    tui::app::key q
    testframework::assert_equal "" "${TUI_APP_MODAL}" "q closes the message modal"
}

test_quit() {
    tui::app::reset
    tui::app::key q
    testframework::assert_equal "1" "${TUI_APP_STOP}" "unbound q sets the quit flag"

    tui::app::reset
    tui::app::quit
    testframework::assert_equal "1" "${TUI_APP_STOP}" "tui::app::quit sets the quit flag"
}

main() {
    testframework::init

    testframework::section "Registration / Регистрация"
    test_register

    testframework::section "Focus navigation / Навигация фокуса"
    test_focus_navigation

    testframework::section "Button press / Нажатие кнопки"
    test_button_press

    testframework::section "Bindings / Биндинги"
    test_bind_precedence
    test_binding_args

    testframework::section "Input modal / Модалка ввода"
    test_input_modal
    test_input_modal_prefill

    testframework::section "Confirm modal / Модалка подтверждения"
    test_confirm_modal

    testframework::section "Message modal / Модалка сообщения"
    test_message_modal

    testframework::section "Quit / Выход"
    test_quit

    testframework::summary
}

main "$@"