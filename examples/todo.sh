#!/usr/bin/env bs
# shellcheck shell=bash
# examples/todo.sh — terminal todo list on lib/tui
# examples/todo.sh — терминальный todo list на lib/tui
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

set -euo pipefail

load "core/args"
load "lib/io/streams"
load "lib/tui/tui"

args::flag file value "${HOME}/.todo.tsv"
args::require "$@"

readonly TODO_TASK_FILE="$(args::flag_get file)"

declare -a TODO_TASKS=()
declare -i TODO_SELECT=0
declare -g TODO_INPUT=""
declare -gi TODO_CURSOR=0
declare -gi TODO_CONFIRM_SEL=0
declare -gi TODO_CONFIRM_IDX=0
declare -g TODO_EDIT_MODE="add"

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

todo::toggle() {
  local line="${TODO_TASKS[${1}]}"
  if [[ "${line}" == DONE* ]]; then
    TODO_TASKS[${1}]="OPEN${line#DONE}"
  else
    TODO_TASKS[${1}]="DONE${line#OPEN}"
  fi
}

todo::apply_input() {
  local text="${TODO_INPUT}"
  is::not_empty "${text}" || return 0
  if [[ "${TODO_EDIT_MODE}" == "edit" ]]; then
    local line="${TODO_TASKS[${TODO_SELECT}]}"
    local status="${line%%$'\t'*}"
    TODO_TASKS[${TODO_SELECT}]="${status}"$'\t'"${text}"
  else
    TODO_TASKS+=("OPEN"$'\t'"${text}")
    TODO_SELECT=$(( ${#TODO_TASKS[@]} - 1 ))
  fi
}

todo::delete() {
  arr::splice TODO_TASKS "${TODO_CONFIRM_IDX}" $(( TODO_CONFIRM_IDX + 1 ))
  if (( TODO_SELECT >= ${#TODO_TASKS[@]} )); then
    TODO_SELECT=$(( ${#TODO_TASKS[@]} - 1 ))
  fi
  if (( TODO_SELECT < 0 )); then
    TODO_SELECT=0
  fi
}

todo::open_input() {
  TODO_EDIT_MODE="${1}"
  TODO_INPUT=""
  TODO_CURSOR=0
  if [[ "${TODO_EDIT_MODE}" == "edit" ]]; then
    local line="${TODO_TASKS[${TODO_SELECT}]}"
    TODO_INPUT="${line#*$'\t'}"
    TODO_CURSOR=${#TODO_INPUT}
  fi
  tui::modal::open input todo::modal_input_draw
}

todo::open_confirm() {
  TODO_CONFIRM_SEL=0
  TODO_CONFIRM_IDX="${TODO_SELECT}"
  tui::modal::open confirm todo::modal_confirm_draw
}

todo::modal_input_draw() {
  local title="Add task"
  [[ "${TODO_EDIT_MODE}" == "edit" ]] && title="Edit task"
  local -i w=56 h=5
  tui::center "${w}" "${h}"
  tui::box "${TUI_CENTER_Y}" "${TUI_CENTER_X}" "${w}" "${h}" \
    "${title}" "$(tui::style bold cyan)"
  tui::put $(( TUI_CENTER_Y + 2 )) $(( TUI_CENTER_X + 2 )) "▸"
  tui::input $(( TUI_CENTER_Y + 2 )) $(( TUI_CENTER_X + 4 )) $(( w - 6 )) \
    "${TODO_INPUT}" "${TODO_CURSOR}"
}

todo::modal_confirm_draw() {
  local line="${TODO_TASKS[${TODO_CONFIRM_IDX}]:-}"
  tui::confirm "Delete task" "${line#*$'\t'}" "${TODO_CONFIRM_SEL}"
}

todo::draw() {
  tui::titlebar "  BS Todo  •  ${TODO_TASK_FILE}" "$(tui::style bold bg_blue white)"
  local -i total=${#TODO_TASKS[@]}
  tui::box 3 2 $(( TUI_COLS - 3 )) $(( TUI_LINES - 5 )) \
    "Tasks (${total})" "$(tui::style bold cyan)"
  if (( total == 0 )); then
    tui::put 5 4 "empty — press [a] to add" "$(tui::style dim)"
  else
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
        tui::put $(( 4 + i )) 4 "${mark}" "$(tui::style bold reverse cyan)"
      elif [[ "${status}" == "DONE" ]]; then
        tui::put $(( 4 + i )) 4 "  ✓ ${text}" "$(tui::style dim strike)"
      else
        tui::put $(( 4 + i )) 4 "  · ${text}" ""
      fi
    done
  fi
  tui::statusbar \
    "  ↑↓ select  Enter toggle  a add  e edit  d delete  q quit" \
    "$(tui::style bg_black white)"
}

todo::type() {
  local -r key="${1}"
  case "${key}" in
    ENTER|ESC|BACKSPACE|LEFT|RIGHT|UP|DOWN|TAB|UNKNOWN) return 0 ;;
  esac
  [[ "${#key}" -eq 1 ]] || return 0
  TODO_INPUT="${TODO_INPUT:0:${TODO_CURSOR}}${key}${TODO_INPUT:${TODO_CURSOR}}"
  TODO_CURSOR=$(( TODO_CURSOR + 1 ))
}

main() {
  todo::load
  tui::init

  while true; do
    tui::handle_resize
    tui::buf::clear
    todo::draw
    tui::modal::draw_all
    tui::render
    tui::key_read

    local top
    top="$(tui::modal::top)"
    case "${top}" in
      input)
        case "${TUI_KEY}" in
          ENTER)
            tui::modal::close
            todo::apply_input
            todo::save
            ;;
          ESC) tui::modal::close ;;
          BACKSPACE)
            if (( TODO_CURSOR > 0 )); then
              TODO_INPUT="${TODO_INPUT:0:${TODO_CURSOR}-1}${TODO_INPUT:${TODO_CURSOR}}"
              TODO_CURSOR=$(( TODO_CURSOR - 1 ))
            fi
            ;;
          LEFT)
            if (( TODO_CURSOR > 0 )); then
              TODO_CURSOR=$(( TODO_CURSOR - 1 ))
            fi
            ;;
          RIGHT)
            if (( TODO_CURSOR < ${#TODO_INPUT} )); then
              TODO_CURSOR=$(( TODO_CURSOR + 1 ))
            fi
            ;;
          *) todo::type "${TUI_KEY}" ;;
        esac
        ;;
      confirm)
        case "${TUI_KEY}" in
          ENTER)
            tui::modal::close
            if (( TODO_CONFIRM_SEL == 0 )); then
              todo::delete
              todo::save
            fi
            ;;
          ESC) tui::modal::close ;;
          LEFT|RIGHT|TAB)
            TODO_CONFIRM_SEL=$(( 1 - TODO_CONFIRM_SEL ))
            ;;
          y|Y|д|Д)
            tui::modal::close
            todo::delete
            todo::save
            ;;
          n|N|н|Н) tui::modal::close ;;
        esac
        ;;
      *)
        case "${TUI_KEY}" in
          q|Q|й|Й) break ;;
          UP|k|K|ц|Ц)
            if (( TODO_SELECT > 0 )); then
              TODO_SELECT=$(( TODO_SELECT - 1 ))
            fi
            ;;
          DOWN|j|J|о|О)
            if (( TODO_SELECT < ${#TODO_TASKS[@]} - 1 )); then
              TODO_SELECT=$(( TODO_SELECT + 1 ))
            fi
            ;;
          ENTER)
            if (( ${#TODO_TASKS[@]} > 0 )); then
              todo::toggle "${TODO_SELECT}"
              todo::save
            fi
            ;;
          a|A|ф|Ф) todo::open_input add ;;
          e|E|у|У)
            if (( ${#TODO_TASKS[@]} > 0 )); then
              todo::open_input edit
            fi
            ;;
          d|D|в|В)
            if (( ${#TODO_TASKS[@]} > 0 )); then
              todo::open_confirm
            fi
            ;;
        esac
        ;;
    esac
  done

  tui::quit
  io::streams::print "Tasks saved: ${TODO_TASK_FILE} (${#TODO_TASKS[@]})"
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
