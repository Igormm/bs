#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/elements/confirm.sh — centered yes/no confirmation dialog
# lib/ui/elements/confirm.sh — центрированный диалог подтверждения да/нет
#
# Run directly to see the element / Запуск напрямую — показать элемент:
#   bs run lib/ui/elements/confirm.sh

# @depends core/lang, lib/tui/tui

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_ELEMENTS_CONFIRM" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../tui/tui.sh"

# @description Draw a centered yes/no dialog.
# @description Нарисовать центрированный диалог да/нет.
# @param $1 Title / Заголовок
# @param $2 Message / Сообщение
# @param $3 [optional] Selection: 0 = Yes, 1 = No / Выбор: 0 = Да, 1 = Нет
ui::elements::confirm::draw() {
    local -r title="${1:-}" message="${2:-}" sel="${3:-0}"
    local -i w=56 h=8
    (( w > TUI_COLS - 8 )) && w=$(( TUI_COLS - 8 ))

    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local st
    st="$(tui::style bold cyan)"
    tui::box "${by}" "${bx}" "${w}" "${h}" "${title}" "${st}"
    tui::put $(( by + 2 )) $(( bx + 2 )) "${message:0:$(( w - 4 ))}"
    if (( sel == 0 )); then
        tui::put $(( by + 4 )) $(( bx + 4 )) "[ Да / Yes ]" "$(tui::style reverse green)"
        tui::put $(( by + 4 )) $(( bx + 16 )) "[ Нет / No ]"
    else
        tui::put $(( by + 4 )) $(( bx + 4 )) "[ Да / Yes ]"
        tui::put $(( by + 4 )) $(( bx + 16 )) "[ Нет / No ]" "$(tui::style reverse red)"
    fi
    tui::put $(( by + 6 )) $(( bx + 2 )) "←/→ + Enter — подтверждение · ESC — отмена / cancel" "$(tui::style dim)"
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    load "lib/tui/tui"
    tui::init
    tui::buf::clear
    ui::elements::confirm::draw "Confirm / Подтверждение" "Удалить задачу? / Delete the task?" 0
    tui::render
    tui::key_read >/dev/null
    tui::quit
fi