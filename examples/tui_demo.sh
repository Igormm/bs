#!/usr/bin/env bs
# shellcheck shell=bash
# examples/tui_demo.sh — TUI framework demo (opencode/Claude-style)
# examples/tui_demo.sh — демо TUI-фреймворка (в стиле opencode/Claude)

# Запуск / Run:
#   ./bs run examples/tui_demo.sh
#   ./examples/tui_demo.sh
#
# Клавиши / Keys:
#   ←→            переключение секций (Tasks/System/About)
#   ↑↓ j k        выбор в списке
#   Enter         зачеркнуть/вернуть (Tasks)
#   a             модальное окно ввода
#   d             модальное подтверждение удаления
#   p             демо прогресса и спиннера
#   F5            перезагрузка (спиннер)
#   q             выход
#   мышь          клик по списку выбирает задачу

load "lib/tui/tui"

# ==========================================
# State / Состояние
# ==========================================

readonly DEMO_FILE="${HOME}/.tui_demo.tsv"
declare -a DEMO_TASKS=()
declare -a DEMO_SECTIONS=("Tasks" "System" "About")
declare -i DEMO_SECTION=0
declare -i DEMO_SELECT=0
declare -i DEMO_FRAME=0
declare -i DEMO_PROGRESS=0
declare -i DEMO_SHOW_PROGRESS=0
declare -g DEMO_MODAL_INPUT=""
declare -g DEMO_MODAL_CURSOR=0
declare -g DEMO_CONFIRM_SEL=0
declare -g DEMO_CONFIRM_IDX=0

# ==========================================
# Data / Данные
# ==========================================

demo::load() {
  DEMO_TASKS=()
  if is::file "${DEMO_FILE}"; then
    mapfile -t DEMO_TASKS < "${DEMO_FILE}"
  fi
}

demo::save() {
  local tmp="${DEMO_FILE}.tmp"
  : > "${tmp}"
  local line
  for line in "${DEMO_TASKS[@]}"; do
    printf '%s\n' "${line}" >> "${tmp}"
  done
  mv -f -- "${tmp}" "${DEMO_FILE}"
}

# ==========================================
# Draw / Отрисовка
# ==========================================

demo::draw_title() {
  local st
  st="$(tui::style bold bg_blue white)"
  tui::titlebar "  BS TUI Framework  •  $(date '+%H:%M:%S')  •  ${TUI_COLS}x${TUI_LINES}" "${st}"
}

demo::draw_sidebar() {
  local st_box st_sel
  st_box="$(tui::style bold magenta)"
  tui::box 2 1 20 7 "Sections" "${st_box}"
  local -i i
  for (( i = 0; i < ${#DEMO_SECTIONS[@]}; i++ )); do
    if (( i == DEMO_SECTION )); then
      tui::put $(( 3 + i )) 3 "▸ ${DEMO_SECTIONS[${i}]}" "$(tui::style bold reverse white)"
    else
      tui::put $(( 3 + i )) 3 "  ${DEMO_SECTIONS[${i}]}" ""
    fi
  done
}

demo::draw_tasks() {
  local st_box
  st_box="$(tui::style bold cyan)"
  local -i total=${#DEMO_TASKS[@]}
  tui::box 2 23 56 $(( TUI_LINES - 5 )) "Tasks (${total})" "${st_box}"
  (( total == 0 )) && { tui::put 4 25 "empty — press [a] to add" "$(tui::style dim)"; return 0; }

  local -i vis=$(( TUI_LINES - 7 ))
  local -i offset=0
  (( DEMO_SELECT < offset )) && offset=${DEMO_SELECT}
  (( DEMO_SELECT >= offset + vis )) && offset=$(( DEMO_SELECT - vis + 1 ))

  local -i i idx
  for (( i = 0; i < vis; i++ )); do
    idx=$(( offset + i ))
    (( idx >= total )) && break
    local line="${DEMO_TASKS[${idx}]}"
    local status="${line%%$'\t'*}"
    local text="${line#*$'\t'}"
    if (( idx == DEMO_SELECT )); then
      local sel_st
      sel_st="$(tui::style bold reverse cyan)"
      case "${status}" in
        DONE) tui::put $(( 3 + i )) 25 "▸ ✓ ${text}" "${sel_st}" ;;
        *)    tui::put $(( 3 + i )) 25 "▸   ${text}" "${sel_st}" ;;
      esac
    else
      case "${status}" in
        DONE) tui::put $(( 3 + i )) 25 "  ✓ ${text}" "$(tui::style dim strike)" ;;
        *)    tui::put $(( 3 + i )) 25 "  · ${text}" "" ;;
      esac
    fi
  done
  tui::scrollbar 3 $(( TUI_LINES - 6 )) "${total}" "${offset}" "${vis}"
}

demo::draw_system() {
  local st_box
  st_box="$(tui::style bold green)"
  tui::box 2 23 56 $(( TUI_LINES - 5 )) "System" "${st_box}"
  tui::put 4 25 "kernel:  $(uname -sr 2>/dev/null)"
  tui::put 5 25 "arch:    $(uname -m 2>/dev/null)"
  tui::put 6 25 "cpu:     $(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null)"
  tui::put 7 25 "cores:   $(nproc 2>/dev/null)"
  tui::put 8 25 "mem:     $(free -h 2>/dev/null | awk '/Mem/{print $2}')"
  tui::put 9 25 "uptime:  $(awk '{print int($1/3600)"h "int(($1%3600)/60)"m"}' /proc/uptime 2>/dev/null)"
}

demo::draw_about() {
  local st_box
  st_box="$(tui::style bold yellow)"
  tui::box 2 23 56 $(( TUI_LINES - 5 )) "About" "${st_box}"
  tui::put 4 25 "BS TUI framework — pure bash, zero deps."
  tui::put 5 25 "Double-buffered diff render, truecolor,"
  tui::put 6 25 "full key parser (arrows/F/Ctrl/Alt/mouse),"
  tui::put 7 25 "widgets: list, input, confirm, menu,"
  tui::put 8 25 "progress, spinner, scrollbar, modal stack."
  tui::put 9 25 "Strike-through, reverse, 256+truecolor."
}

demo::draw_progress() {
  (( DEMO_SHOW_PROGRESS == 1 )) || return 0
  tui::progress $(( TUI_LINES - 3 )) 23 56 "${DEMO_PROGRESS}"
  tui::spinner $(( TUI_LINES - 3 )) 1 "${DEMO_FRAME}" "$(tui::style bold cyan)"
  tui::put $(( TUI_LINES - 3 )) 3 "loading..." "$(tui::style dim)"
}

demo::draw_status() {
  local st
  st="$(tui::style bg_black white)"
  tui::statusbar "  ←→ sections   ↑↓ select   Enter toggle   a add   d delete   p progress   F5 reload   q quit" "${st}"
}

demo::modal_input_draw() {
  local st
  st="$(tui::style bold cyan)"
  local -i w=56 h=5 bx by
  tui::center "${w}" "${h}"
  bx="${TUI_CENTER_X}"; by="${TUI_CENTER_Y}"
  tui::box "${by}" "${bx}" "${w}" "${h}" "Add task" "${st}"
  tui::put $(( by + 2 )) $(( bx + 2 )) "▸"
  tui::input $(( by + 2 )) $(( bx + 4 )) $(( w - 6 )) "${DEMO_MODAL_INPUT}" "${DEMO_MODAL_CURSOR}"
}

demo::modal_confirm_draw() {
  local -r line="${DEMO_TASKS[${DEMO_CONFIRM_IDX}]:-}"
  local text="${line#*$'\t'}"
  tui::confirm "Delete task" "remove: ${text}" "${DEMO_CONFIRM_SEL}"
}

demo::draw_frame() {
  demo::draw_title
  demo::draw_sidebar
  case "${DEMO_SECTION}" in
    0) demo::draw_tasks ;;
    1) demo::draw_system ;;
    2) demo::draw_about ;;
  esac
  demo::draw_progress
  demo::draw_status
}

# ==========================================
# Actions / Действия
# ==========================================

demo::open_input() {
  DEMO_MODAL_INPUT=""
  DEMO_MODAL_CURSOR=0
  tui::modal::open input demo::modal_input_draw
}

demo::open_confirm() {
  DEMO_CONFIRM_SEL=0
  DEMO_CONFIRM_IDX="${DEMO_SELECT}"
  tui::modal::open confirm demo::modal_confirm_draw
}

demo::add_task() {
  DEMO_TASKS+=("OPEN"$'\t'"${DEMO_MODAL_INPUT}")
  DEMO_SELECT=$(( ${#DEMO_TASKS[@]} - 1 ))
}

demo::delete_task() {
  arr::splice DEMO_TASKS "${DEMO_CONFIRM_IDX}" $(( DEMO_CONFIRM_IDX + 1 ))
  (( DEMO_SELECT >= ${#DEMO_TASKS[@]} )) && DEMO_SELECT=$(( ${#DEMO_TASKS[@]} - 1 ))
  (( DEMO_SELECT < 0 )) && DEMO_SELECT=0
  return 0
}

demo::toggle_task() {
  local line="${DEMO_TASKS[${1}]}"
  if [[ "${line}" == DONE* ]]; then
    DEMO_TASKS[${1}]="OPEN${line#DONE}"
  else
    DEMO_TASKS[${1}]="DONE${line#OPEN}"
  fi
}

# ==========================================
# Main loop / Главный цикл
# ==========================================

main() {
  demo::load
  tui::init

  while true; do
    tui::handle_resize
    tui::buf::clear
    demo::draw_frame
    tui::modal::draw_all
    tui::render
    tui::key_read

    local top
    top="$(tui::modal::top)"
    case "${top}" in
      input)
        case "${TUI_KEY}" in
          ENTER) tui::modal::close; demo::add_task; demo::save ;;
          ESC)   tui::modal::close ;;
          BACKSPACE)
            (( DEMO_MODAL_CURSOR > 0 )) || break
            DEMO_MODAL_INPUT="${DEMO_MODAL_INPUT:0:${DEMO_MODAL_CURSOR}-1}${DEMO_MODAL_INPUT:${DEMO_MODAL_CURSOR}}"
            DEMO_MODAL_CURSOR=$(( DEMO_MODAL_CURSOR - 1 )) ;;
          LEFT)  (( DEMO_MODAL_CURSOR > 0 )) && DEMO_MODAL_CURSOR=$(( DEMO_MODAL_CURSOR - 1 )) ;;
          RIGHT) (( DEMO_MODAL_CURSOR < ${#DEMO_MODAL_INPUT} )) && DEMO_MODAL_CURSOR=$(( DEMO_MODAL_CURSOR + 1 )) ;;
          *)     DEMO_MODAL_INPUT="${DEMO_MODAL_INPUT:0:${DEMO_MODAL_CURSOR}}${TUI_KEY}${DEMO_MODAL_INPUT:${DEMO_MODAL_CURSOR}}"
                 DEMO_MODAL_CURSOR=$(( DEMO_MODAL_CURSOR + 1 )) ;;
        esac
        ;;
      confirm)
        case "${TUI_KEY}" in
          ENTER) tui::modal::close
                 (( DEMO_CONFIRM_SEL == 0 )) && { demo::delete_task; demo::save; } ;;
          ESC)   tui::modal::close ;;
          LEFT|RIGHT|TAB) DEMO_CONFIRM_SEL=$(( 1 - DEMO_CONFIRM_SEL )) ;;
          y|Y|д|Д) tui::modal::close; demo::delete_task; demo::save ;;
          n|N|н|Н) tui::modal::close ;;
        esac
        ;;
      *)
        case "${TUI_KEY}" in
          q|Q|й|Й) break ;;
          LEFT)  (( DEMO_SECTION > 0 )) && DEMO_SECTION=$(( DEMO_SECTION - 1 )) ;;
          RIGHT) (( DEMO_SECTION < ${#DEMO_SECTIONS[@]} - 1 )) && DEMO_SECTION=$(( DEMO_SECTION + 1 )) ;;
          UP|k|K|ц|Ц) (( DEMO_SELECT > 0 )) && DEMO_SELECT=$(( DEMO_SELECT - 1 )) ;;
          DOWN|j|J|о|О) (( DEMO_SELECT < ${#DEMO_TASKS[@]} - 1 )) && DEMO_SELECT=$(( DEMO_SELECT + 1 )) ;;
          ENTER) (( ${#DEMO_TASKS[@]} > 0 )) && { demo::toggle_task "${DEMO_SELECT}"; demo::save; } ;;
          a|A|ф|Ф) demo::open_input ;;
          d|D|в|В) (( ${#DEMO_TASKS[@]} > 0 )) && demo::open_confirm ;;
          p|P|з|З) DEMO_SHOW_PROGRESS=1; DEMO_PROGRESS=0 ;;
          F5) DEMO_FRAME=0 ;;
          MOUSE)
            # клик по списку (Tasks): row 3.., col 23.. / click on the list
            if (( TUI_MOUSE_BUTTON == 0 && TUI_MOUSE_X >= 23 && TUI_MOUSE_Y >= 3 )); then
              local -i row=$(( TUI_MOUSE_Y - 3 ))
              (( row < ${#DEMO_TASKS[@]} )) && DEMO_SELECT="${row}"
            fi
            ;;
        esac
        ;;
    esac

    # прогресс-анимация / progress animation
    (( DEMO_SHOW_PROGRESS == 1 )) && {
      DEMO_PROGRESS=$(( DEMO_PROGRESS + 3 ))
      (( DEMO_PROGRESS >= 100 )) && DEMO_SHOW_PROGRESS=0
    }
    DEMO_FRAME=$(( DEMO_FRAME + 1 ))
  done

  tui::quit
  printf 'Tasks saved: %s (%d)\n' "${DEMO_FILE}" "${#DEMO_TASKS[@]}"
}

# Запуск при исполнении или через `bs run` (source'ит скрипт),
# пропуск при ручном source (для тестов).
# Run when executed or via `bs run` (which sources); skip on manual source.
if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi