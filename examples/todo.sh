#!/usr/bin/env bs
# shellcheck shell=bash
# examples/todo.sh — terminal todo list on lib/tui/app
# examples/todo.sh — терминальный todo list на lib/tui/app
#
#   ./bs run examples/todo.sh
#   ./bs run examples/todo.sh --file /tmp/tasks.tsv
#
# Keys / Клавиши:
#   ↑↓ j k   select / выбор
#   Enter    toggle / зачеркнуть
#   a        add / добавить
#   e        edit / править
#   d        delete / удалить
#   q        quit / выход

load "core/args"
load "lib/io/streams"
load "lib/tui/app"

args::flag file value "${HOME}/.todo.tsv"
args::require "$@"

readonly TODO_TASK_FILE="$(args::flag_get file)"

declare -a TODO_TASKS=()
declare -i TODO_SELECT=0

todo::load() {
    TODO_TASKS=()
    if is::file "${TODO_TASK_FILE}"; then
        mapfile -t TODO_TASKS < "${TODO_TASK_FILE}"
    fi
}

todo::save() {
    local tmp="${TODO_TASK_FILE}.tmp"
    local line
    : > "${tmp}"
    for line in "${TODO_TASKS[@]}"; do
        printf '%s\n' "${line}" >> "${tmp}"
    done
    mv -f -- "${tmp}" "${TODO_TASK_FILE}"
}

todo::toggle_selected() {
    local line="${TODO_TASKS[${TODO_SELECT}]}"
    if [[ "${line}" == DONE* ]]; then
        TODO_TASKS[${TODO_SELECT}]="OPEN${line#DONE}"
    else
        TODO_TASKS[${TODO_SELECT}]="DONE${line#OPEN}"
    fi
    todo::save
}

todo::submit_input() {
    local -r text="${1}"
    is::not_empty "${text}" || return 0
    if [[ "${TODO_EDIT_MODE}" == "edit" ]]; then
        local line="${TODO_TASKS[${TODO_SELECT}]}"
        local status="${line%%$'\t'*}"
        TODO_TASKS[${TODO_SELECT}]="${status}"$'\t'"${text}"
    else
        TODO_TASKS+=("OPEN"$'\t'"${text}")
        TODO_SELECT=$(( ${#TODO_TASKS[@]} - 1 ))
    fi
    todo::save
}

todo::delete() {
    arr::splice TODO_TASKS "${TODO_SELECT}" $(( TODO_SELECT + 1 ))
    if (( TODO_SELECT >= ${#TODO_TASKS[@]} )); then
        TODO_SELECT=$(( ${#TODO_TASKS[@]} - 1 ))
    fi
    if (( TODO_SELECT < 0 )); then
        TODO_SELECT=0
    fi
    todo::save
}

todo::draw_list() {
    local -r r=4 c=4
    local -i total=${#TODO_TASKS[@]}
    if (( total == 0 )); then
        tui::put "${r}" "${c}" "empty — press [a] to add" "$(tui::style dim)"
        return 0
    fi
    local -i vis=$(( TUI_LINES - 8 ))
    local -i offset=0
    (( TODO_SELECT < offset )) && offset=${TODO_SELECT}
    (( TODO_SELECT >= offset + vis )) && offset=$(( TODO_SELECT - vis + 1 ))
    local -i i idx
    for (( i = 0; i < vis; i++ )); do
        idx=$(( offset + i ))
        (( idx >= total )) && break
        local line="${TODO_TASKS[${idx}]}"
        local status="${line%%$'\t'*}"
        local text="${line#*$'\t'}"
        if (( idx == TODO_SELECT )); then
            local mark="▸ · ${text}"
            [[ "${status}" == "DONE" ]] && mark="▸ ✓ ${text}"
            tui::put $(( r + i )) "${c}" "${mark}" "$(tui::style bold reverse cyan)"
        elif [[ "${status}" == "DONE" ]]; then
            tui::put $(( r + i )) "${c}" "  ✓ ${text}" "$(tui::style dim strike)"
        else
            tui::put $(( r + i )) "${c}" "  · ${text}" ""
        fi
    done
}

declare -g TODO_EDIT_MODE="add"

todo::add() {
    TODO_EDIT_MODE="add"
    tui::app::input_modal "Add task" todo::submit_input
}

todo::edit() {
    (( ${#TODO_TASKS[@]} > 0 )) || return 0
    TODO_EDIT_MODE="edit"
    local line="${TODO_TASKS[${TODO_SELECT}]}"
    tui::app::input_modal "Edit task" todo::submit_input "" "${line#*$'\t'}"
}

todo::ask_delete() {
    (( ${#TODO_TASKS[@]} > 0 )) || return 0
    local line="${TODO_TASKS[${TODO_SELECT}]}"
    tui::app::confirm_modal "Delete task" "${line#*$'\t'}" todo::delete
}

todo::move() {
    local -r dir="${1}"
    if [[ "${dir}" == "up" ]]; then
        (( TODO_SELECT > 0 )) && TODO_SELECT=$(( TODO_SELECT - 1 ))
    else
        (( TODO_SELECT < ${#TODO_TASKS[@]} - 1 )) && TODO_SELECT=$(( TODO_SELECT + 1 ))
    fi
}

main() {
    todo::load
    tui::app::window list "Tasks" 3 2 $(( TUI_COLS - 3 )) $(( TUI_LINES - 5 ))
    tui::app::draw_hook todo::draw_list
    tui::app::bind "UP|k|K|ц|Ц" todo::move up
    tui::app::bind "DOWN|j|J|о|О" todo::move down
    tui::app::bind "ENTER" todo::toggle_selected
    tui::app::bind "a|A|ф|Ф" todo::add
    tui::app::bind "e|E|у|У" todo::edit
    tui::app::bind "d|D|в|В" todo::ask_delete
    tui::app::statusbar "Tasks: ${#TODO_TASKS[@]}   ↑↓ select  Enter toggle  a add  e edit  d delete  q quit"
    tui::app::run
    io::streams::print "Tasks saved: ${TODO_TASK_FILE} (${#TODO_TASKS[@]})"
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi