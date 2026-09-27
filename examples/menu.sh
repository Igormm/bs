#!/usr/bin/env bs
# shellcheck shell=bash
# examples/menu.sh — minimal interactive TUI menu (lib/tui)
# examples/menu.sh — минимальное интерактивное TUI-меню (lib/tui)

# Запуск / Run:
#   ./bs run examples/menu.sh
#
# Клавиши / Keys:
#   ↑↓ j k    выбор пункта / move selection
#   Enter     выполнить действие / run the action
#   q         выход / quit

load "lib/io/streams"
load "lib/tui/tui"

main() {
    local -a items=("Run checks" "Show status" "Quit")
    local -i sel=0

    tui::init
    while true; do
        tui::handle_resize
        tui::buf::clear
        tui::menu 2 2 items "${sel}" "Menu"
        tui::render
        tui::key_read

        case "${TUI_KEY}" in
            UP|k)
                if (( sel > 0 )); then
                    sel=$(( sel - 1 ))
                fi
                ;;
            DOWN|j)
                if (( sel < ${#items[@]} - 1 )); then
                    sel=$(( sel + 1 ))
                fi
                ;;
            ENTER)
                tui::quit
                case "${sel}" in
                    0) io::streams::print "Running checks..." ;;
                    1) io::streams::print "All systems OK." ;;
                    2) return 0 ;;
                esac
                break
                ;;
            q)
                tui::quit
                return 0
                ;;
        esac
    done
}

# Запуск при исполнении или через `bs run` (source'ит скрипт),
# пропуск при ручном source (для тестов).
# Run when executed or via `bs run` (which sources); skip on manual source.
if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi