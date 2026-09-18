#!/usr/bin/env bs
# shellcheck shell=bash
# examples/todo.sh — terminal todo list with modal windows (pure bash TUI)
# examples/todo.sh — терминальный todo list с модальными окнами (TUI)

# Пример применения фреймворка: декларативные args, коллекции core/lang,
# чистый bash-TUI (ANSI + read) без внешних зависимостей.
# Framework demo: declarative args, core/lang collections, pure bash TUI.

load "core/args"
load "core/lang"

# ==========================================
# Config / Конфигурация
# ==========================================

args::flag file value "${HOME}/.todo.tsv"
args::require "$@"

# Данные: строки "OPEN\tтекст" / "DONE\tтекст"
# Data: lines "OPEN\ttext" / "DONE\ttext"
readonly TODO_TASK_FILE="$(args::flag_get file)"

# Состояние / State
declare -a TODO_TASKS=()
declare -i TODO_SELECT=0

# ==========================================
# Терминал: ANSI-примитивы / Terminal primitives
# ==========================================

todo::hide_cursor()   { printf '\e[?25l'; }
todo::show_cursor()   { printf '\e[?25h'; }
todo::move()          { printf '\e[%d;%dH' "$1" "$2"; }
todo::clear_screen()  { printf '\e[2J\e[H'; }
todo::enter_alt()     { printf '\e[?1049h'; }
todo::leave_alt()     { printf '\e[?1049l'; }
todo::bold()          { printf '\e[1m'; }
todo::dim()           { printf '\e[2m'; }
todo::reverse()       { printf '\e[7m'; }
todo::strike()        { printf '\e[9m'; }
todo::reset_style()   { printf '\e[0m'; }

# @description Размер терминала / Terminal size (fallback 80x24).
todo::size() {
  local cols lines
  if is::command tput; then
    cols="$(tput cols 2>/dev/null || printf 80)"
    lines="$(tput lines 2>/dev/null || printf 24)"
  else
    cols=80
    lines=24
  fi
  TODO_COLS="${cols}"
  TODO_LINES="${lines}"
}

# @description Модальное окно с рамкой (центрированное).
# @description Modal box with a border (centered).
# @param $1 title / заголовок
# @param $2 height / высота
# @param $3 width / ширина
todo::box() {
  local -r title="$1" h="$2" w="$3"
  local x y
  x=$(( (TODO_COLS - w) / 2 ))
  y=$(( (TODO_LINES - h) / 2 ))
  local i
  todo::move "${y}" "${x}"; printf '╔═ %s %s╗' "${title}" "$(str::repeat "═" $(( w - 6 - ${#title} )))"
  for (( i = 1; i < h - 1; i++ )); do
    todo::move "$(( y + i ))" "${x}"; printf '║'; todo::move "$(( y + i ))" "$(( x + w - 1 ))"; printf '║'
  done
  todo::move "$(( y + h - 1 ))" "${x}"; printf '╚%s╝' "$(str::repeat "═" $(( w - 2 )))"
  TODO_BOX_X="${x}"
  TODO_BOX_Y="${y}"
  TODO_BOX_W="${w}"
}

# @description Текст внутри окна (с отступами).
# @description Text inside the box (with padding).
# @param $1 row (0-based from box top), $2 text
todo::box_text() {
  local -r row="$1" text="$2"
  todo::move "$(( TODO_BOX_Y + 1 + row ))" "$(( TODO_BOX_X + 2 ))"
  printf '%s' "${text:0:$(( TODO_BOX_W - 4 ))}"
}

# ==========================================
# Клавиатура / Keyboard
# ==========================================

# @description Прочитать клавишу, распознать стрелки.
# @description Read a key, translate arrows.
# @stdout key name: UP DOWN LEFT RIGHT ENTER ESC or the char
todo::key() {
  local k seq
  IFS= read -r -s -n1 k || k=""
  if [[ "${k}" == $'\e' ]]; then
    IFS= read -r -s -n2 -t 0.05 seq || seq=""
    case "${seq}" in
      '[A') printf 'UP\n' ;;
      '[B') printf 'DOWN\n' ;;
      '[C') printf 'RIGHT\n' ;;
      '[D') printf 'LEFT\n' ;;
      *)    printf 'ESC\n' ;;
    esac
    return 0
  fi
  case "${k}" in
    $'\n'|"") printf 'ENTER\n' ;;
    $'\x7f'|$'\b') printf 'BACKSPACE\n' ;;
    *) printf '%s\n' "${k}" ;;
  esac
}

# ==========================================
# Данные / Data
# ==========================================

# @description Загрузить задачи из файла.
# @description Load tasks from the file.
todo::load() {
  TODO_TASKS=()
  if is::file "${TODO_TASK_FILE}"; then
    mapfile -t TODO_TASKS < "${TODO_TASK_FILE}"
  fi
}

# @description Сохранить задачи (атомарно: tmp + mv).
# @description Save tasks (atomically: tmp + mv).
todo::save() {
  local tmp="${TODO_TASK_FILE}.tmp"
  : > "${tmp}"
  local line
  for line in "${TODO_TASKS[@]}"; do
    printf '%s\n' "${line}" >> "${tmp}"
  done
  mv -f -- "${tmp}" "${TODO_TASK_FILE}"
}

# ==========================================
# Рендер / Rendering
# ==========================================

todo::render() {
  local i line status text
  todo::clear_screen
  todo::move 1 1
  todo::bold; printf ' BS Todo '; todo::reset_style
  printf '  [↑↓] move  [Enter] toggle  [a] add  [e] edit  [d] delete  [q] quit\n'
  printf '%s\n' "$(str::repeat "─" "${TODO_COLS}")"

  for (( i = 0; i < ${#TODO_TASKS[@]}; i++ )); do
    line="${TODO_TASKS[${i}]}"
    status="${line%%$'\t'*}"
    text="${line#*$'\t'}"
    todo::move "$(( i + 3 ))" 1
    if (( i == TODO_SELECT )); then
      todo::reverse
      printf '▶ '
    else
      printf '  '
    fi
    case "${status}" in
      DONE) todo::dim; todo::strike; printf '✓ %s' "${text}"; todo::reset_style ;;
      *)    printf '· %s' "${text}"; todo::reset_style ;;
    esac
  done

  # Строка статуса / Status line
  local done_count=$((0)) open_count=$((0))
  for line in "${TODO_TASKS[@]}"; do
    [[ "${line}" == DONE* ]] && done_count=$(( done_count + 1 )) || open_count=$(( open_count + 1 ))
  done
  todo::move "$(( TODO_LINES - 1 ))" 1
  todo::dim
  printf '%s: %d open, %d done — %s\n' "${TODO_TASK_FILE}" "${open_count}" "${done_count}" "$(date '+%H:%M')"
  todo::reset_style
}

# ==========================================
# Модальные окна / Modal windows
# ==========================================

# @description Модальное окно ввода текста.
# @description Modal text input window.
# @param $1 title / заголовок
# @param $2 initial value / начальное значение
# @stdout введённый текст (ESC — пусто и код 1)
# @return 0 ok, 1 cancelled
TODO_INPUT_RESULT=""
todo::input_modal() {
  local -r title="$1"
  local text="${2-}"
  local key
  while true; do
    todo::clear_screen
    todo::box "${title}" 5 60
    todo::box_text 1 "▸ ${text}_"
    key="$(todo::key)"
    case "${key}" in
      ENTER) break ;;
      ESC)   return 1 ;;
      BACKSPACE) text="${text%?}" ;;
      *)     text+="${key}" ;;
    esac
  done
  TODO_INPUT_RESULT="${text}"
  return 0
}

# @description Модальное подтверждение (Yes/No).
# @description Modal confirmation (Yes/No).
# @param $1 title / заголовок
# @param $2 message / сообщение
# @return 0 yes, 1 no
todo::confirm_modal() {
  local -r title="$1" message="$2"
  local key
  while true; do
    todo::clear_screen
    todo::box "${title}" 5 52
    todo::box_text 1 "${message}"
    todo::box_text 2 "  [ Enter = Yes ]   [ Esc = No ]"
    key="$(todo::key)"
    case "${key}" in
      ENTER) return 0 ;;
      ESC)   return 1 ;;
      y|Y|д|Д) return 0 ;;
      n|N|н|Н) return 1 ;;
    esac
  done
}

# ==========================================
# Действия / Actions
# ==========================================

todo::toggle() {
  local line="${TODO_TASKS[${1}]}"
  if [[ "${line}" == DONE* ]]; then
    TODO_TASKS[${1}]="OPEN${line#DONE}"
  else
    TODO_TASKS[${1}]="DONE${line#OPEN}"
  fi
}

todo::add() {
  if todo::input_modal "Add task / Новая задача"; then
    TODO_TASKS+=("OPEN"$'\t'"${TODO_INPUT_RESULT}")
    TODO_SELECT=$(( ${#TODO_TASKS[@]} - 1 ))
  fi
}

todo::edit() {
  local line="${TODO_TASKS[${1}]}"
  local status="${line%%$'\t'*}" text="${line#*$'\t'}"
  if todo::input_modal "Edit task / Редактировать" "${text}"; then
    TODO_TASKS[${1}]="${status}"$'\t'"${TODO_INPUT_RESULT}"
  fi
}

todo::delete() {
  if todo::confirm_modal "Delete task / Удалить задачу" "${TODO_TASKS[${1}]}"; then
    arr::splice TODO_TASKS "${1}" $(( ${1} + 1 ))
    (( TODO_SELECT >= ${#TODO_TASKS[@]} )) && TODO_SELECT=$(( ${#TODO_TASKS[@]} - 1 ))
    (( TODO_SELECT < 0 )) && TODO_SELECT=0
  fi
}

# ==========================================
# Main / Главный цикл
# ==========================================

main() {
  todo::size
  todo::load
  todo::enter_alt
  todo::hide_cursor
  trap 'todo::show_cursor; todo::leave_alt' EXIT

  local key
  while true; do
    todo::render
    key="$(todo::key)"
    case "${key}" in
      q|Q|й|Й) break ;;
      UP|k|K|ц|Ц)   (( TODO_SELECT > 0 )) && TODO_SELECT=$(( TODO_SELECT - 1 )) ;;
      DOWN|j|J|о|О) (( TODO_SELECT < ${#TODO_TASKS[@]} - 1 )) && TODO_SELECT=$(( TODO_SELECT + 1 )) ;;
      ENTER)        (( ${#TODO_TASKS[@]} > 0 )) && { todo::toggle "${TODO_SELECT}"; todo::save; } ;;
      a|A|ф|Ф)      todo::add; todo::save ;;
      e|E|у|У)      (( ${#TODO_TASKS[@]} > 0 )) && { todo::edit "${TODO_SELECT}"; todo::save; } ;;
      d|D|в|В)      (( ${#TODO_TASKS[@]} > 0 )) && { todo::delete "${TODO_SELECT}"; todo::save; } ;;
    esac
  done

  todo::show_cursor
  todo::leave_alt
  printf 'Tasks saved: %s (%d)\n' "${TODO_TASK_FILE}" "${#TODO_TASKS[@]}"
}

main "$@"