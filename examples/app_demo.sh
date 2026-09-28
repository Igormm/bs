#!/usr/bin/env bs
# shellcheck shell=bash
# examples/app_demo.sh — beginner TUI app: window, buttons, message dialog
# examples/app_demo.sh — TUI для новичков: окно, кнопки, модалка сообщения

# Запуск / Run:
#   ./bs run examples/app_demo.sh
#
# Клавиши / Keys:
#   Tab / ↑↓←→   следующий фокус кнопки / next button focus
#   Enter        нажать кнопку / press the button
#   q            выход / quit

load "lib/tui/app"

main() {
    tui::app::window main "Hello BS" 2 2 30 9
    tui::app::button main greet "Say hello" 3 4
    tui::app::button main quit "Quit" 5 4
    tui::app::on greet app::say_hello
    tui::app::on quit tui::app::quit
    tui::app::focus greet
    tui::app::statusbar "Tab / arrows — next button, Enter — press, q — quit"
    tui::app::run
}

app::say_hello() {
    tui::app::message_modal "Hello" "Hello from BS ${BS_VERSION}!"
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi