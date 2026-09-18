#!/usr/bin/env bs
# shellcheck shell=bash
# lib/tui/tui.sh — terminal UI framework for BS (opencode/Claude-style)
# lib/tui/tui.sh — TUI-фреймворк для BS (в стиле opencode/Claude)

# @depends core/lang, core/utils
# @tier core

# Source Guard
bs::guard "LIB_TUI" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh" "../../core/utils.sh"

# ==========================================
# TUI framework / TUI-фреймворк
#
# Pure bash terminal UI: double-buffered diff renderer, truecolor styles,
# full key parser (arrows/F-keys/Ctrl/Alt/mouse), widgets (list, input,
# confirm, menu, progress, spinner, scrollbar), modal stack.
# Чистый bash TUI: двойной буфер с diff-рендером, truecolor-стили,
# полный парсер клавиш (стрелки/F/Ctrl/Alt/мышь), виджеты (list, input,
# confirm, menu, progress, spinner, scrollbar), стек модальных окон.
#
# Usage / Использование:
#   load "lib/tui"
#   tui::init
#   tui::buf::clear
#   tui::box 2 2 40 8 "title"
#   tui::list 2 4 40 5 items 0
#   tui::render
#   key="$(tui::key_read && printf '%s' "${TUI_KEY}")"  # см. globals
#   tui::quit
#
# Globals / Глобалы: TUI_KEY, TUI_KEY_CHAR, TUI_MOUSE_{X,Y,BUTTON},
#                   TUI_COLS, TUI_LINES, TUI_BUF, TUI_LAST, TUI_MODAL_STACK
# ==========================================

# ==========================================
# Terminal state / Состояние терминала
# ==========================================

declare -g TUI_ACTIVE=0
declare -g TUI_COLS=80
declare -g TUI_LINES=24
declare -g TUI_TRUECOLOR=0
declare -g TUI_STTY_SAVE=""
declare -g TUI_KEY=""
declare -g TUI_KEY_CHAR=""
declare -g TUI_MOUSE_X=0
declare -g TUI_MOUSE_Y=0
declare -g TUI_MOUSE_BUTTON=0
declare -g TUI_RESIZED=0

# Screen buffer / Буфер экрана: "r,c" → char; "r,c:s" → style
declare -gA TUI_BUF=()
declare -gA TUI_BUF_STYLE=()
declare -gA TUI_LAST=()
declare -gA TUI_LAST_STYLE=()

# Modal stack / Стек модальных окон: name → draw function
declare -gA TUI_MODAL_DRAW=()
declare -ga TUI_MODAL_STACK=()

# ==========================================
# ANSI primitives / ANSI-примитивы
# ==========================================

tui::enter_alt() { printf '\e[?1049h'; }
tui::leave_alt() { printf '\e[?1049l'; }
tui::hide_cursor() { printf '\e[?25l'; }
tui::show_cursor() { printf '\e[?25h'; }
tui::cursor_to()  { printf '\e[%d;%dH' "$1" "$2"; }
tui::clear_screen() { printf '\e[2J\e[H'; }
tui::mouse_on()   { printf '\e[?1000h\e[?1006h'; }
tui::mouse_off()  { printf '\e[?1000l\e[?1006l'; }

# @description Detect truecolor support (COLORTERM).
# @description Определить поддержку truecolor (COLORTERM).
tui::detect_color() {
  case "${COLORTERM:-}" in
    truecolor|24bit) TUI_TRUECOLOR=1 ;;
    *) TUI_TRUECOLOR=0 ;;
  esac
}

# @description Terminal size (fallback 80x24) / Размер терминала.
tui::size() {
  local cols lines
  if is::command tput; then
    cols="$(tput cols 2>/dev/null || printf 80)"
    lines="$(tput lines 2>/dev/null || printf 24)"
  else
    cols=80
    lines=24
  fi
  TUI_COLS="${cols}"
  TUI_LINES="${lines}"
}

# @description Initialize the TUI: raw mode, alt screen, traps.
# @description Инициализация TUI: raw-режим, alt-экран, обработчики.
tui::init() {
  TUI_STTY_SAVE="$(stty -g 2>/dev/null || true)"
  stty -icanon -echo 2>/dev/null || true
  tui::enter_alt
  tui::hide_cursor
  tui::mouse_on
  tui::detect_color
  tui::size
  tui::buf::clear
  trap 'tui::quit' EXIT
  trap 'TUI_RESIZED=1' WINCH
  TUI_ACTIVE=1
}

# @description Restore the terminal / Восстановить терминал.
tui::quit() {
  (( TUI_ACTIVE == 1 )) || return 0
  TUI_ACTIVE=0
  tui::mouse_off
  tui::show_cursor
  tui::leave_alt
  stty "${TUI_STTY_SAVE}" 2>/dev/null || true
}

# @description Handle resize: re-read size, clear buffers.
# @description Обработать изменение размера: перечитать, очистить буферы.
tui::handle_resize() {
  if (( TUI_RESIZED == 1 )); then
    tui::size
    TUI_BUF=()
    TUI_BUF_STYLE=()
    TUI_LAST=()
    TUI_LAST_STYLE=()
    TUI_RESIZED=0
  fi
}

# ==========================================
# Styles / Стили
# ==========================================

# @description Build an SGR style code.
# @description Собрать SGR-код стиля.
#   Named colors: black red green yellow blue magenta cyan white
#   bright_<color>, gray, orange. Hex colors (truecolor): #RRGGBB.
#   Attributes: bold dim italic underline strike reverse blink
# @param $@ style words / слова стиля
# @stdout SGR sequence without \e[0m / SGR-последовательность
# @example
#   st="$(tui::style bold blue)"           # "\e[1;34m"
#   st="$(tui::style bold bg:blue #ff8800)"
tui::style() {
  local -a parts=()
  local w
  for w in "$@"; do
    case "${w}" in
      bold)      parts+=(1) ;;
      dim)       parts+=(2) ;;
      italic)    parts+=(3) ;;
      underline) parts+=(4) ;;
      strike)    parts+=(9) ;;
      blink)     parts+=(5) ;;
      reverse)   parts+=(7) ;;
      black)     parts+=(30) ;;
      red)       parts+=(31) ;;
      green)     parts+=(32) ;;
      yellow)    parts+=(33) ;;
      blue)      parts+=(34) ;;
      magenta)   parts+=(35) ;;
      cyan)      parts+=(36) ;;
      white)     parts+=(37) ;;
      gray)      parts+=(90) ;;
      orange)    parts+=(38\;5\;214) ;;
      bright_black)   parts+=(90) ;;
      bright_red)     parts+=(91) ;;
      bright_green)   parts+=(92) ;;
      bright_yellow)  parts+=(93) ;;
      bright_blue)    parts+=(94) ;;
      bright_magenta) parts+=(95) ;;
      bright_cyan)    parts+=(96) ;;
      bright_white)   parts+=(97) ;;
      bg:*)      parts+=("4${w#bg:}" ) ;;
      bg_black)  parts+=(40) ;;
      bg_red)    parts+=(41) ;;
      bg_green)  parts+=(42) ;;
      bg_yellow) parts+=(43) ;;
      bg_blue)   parts+=(44) ;;
      bg_magenta) parts+=(45) ;;
      bg_cyan)   parts+=(46) ;;
      bg_white)  parts+=(47) ;;
      # hex-цвета (truecolor) / hex colors
      \#*)
        if (( TUI_TRUECOLOR == 1 )); then
          local hex="${w#\#}"
          local r g b
          r=$(( 16#${hex:0:2} )); g=$(( 16#${hex:2:2} )); b=$(( 16#${hex:4:2} ))
          parts+=("38;2;${r};${g};${b}")
        fi
        ;;
      bg:\#*)
        if (( TUI_TRUECOLOR == 1 )); then
          local hex="${w#bg:\#}"
          local r g b
          r=$(( 16#${hex:0:2} )); g=$(( 16#${hex:2:2} )); b=$(( 16#${hex:4:2} ))
          parts+=("48;2;${r};${g};${b}")
        fi
        ;;
    esac
  done
  if (( ${#parts[@]} > 0 )); then
    printf '\e[%sm' "$(str::join_parts "${parts[@]}")"
  fi
}

# @private
# @description Join style parts with ';' / Склеить части стиля ';'.
str::join_parts() {
  local out="" p
  for p in "$@"; do
    is::empty "${out}" || out+=";"
    out+="${p}"
  done
  printf '%s' "${out}"
}

# ==========================================
# Screen buffer / Буфер экрана (double-buffer)
# ==========================================

tui::buf::clear() {
  TUI_BUF=()
  TUI_BUF_STYLE=()
  local -i r c
  for (( r = 0; r < TUI_LINES; r++ )); do
    for (( c = 0; c < TUI_COLS; c++ )); do
      TUI_BUF["${r},${c}"]=" "
      TUI_BUF_STYLE["${r},${c}"]=""
    done
  done
}

# @description Put a styled string at (r,c).
# @description Положить строку со стилем в (r,c).
# @param $1 row (1-based), $2 col, $3 text, $4 [style]
tui::put() {
  local -r r="$1" c="$2" text="$3" style="${4-}"
  local -i i rr=$(( r - 1 )) cc=$(( c - 1 ))
  local ch
  for (( i = 0; i < ${#text}; i++ )); do
    (( cc >= TUI_COLS )) && break
    ch="${text:i:1}"
    TUI_BUF["${rr},${cc}"]="${ch}"
    TUI_BUF_STYLE["${rr},${cc}"]="${style}"
    cc=$(( cc + 1 ))
  done
}

# @description Fill a rectangle / Залить прямоугольник.
# @param $1 row, $2 col, $3 width, $4 height, $5 [char], $6 [style]
tui::fill() {
  local -r r="$1" c="$2" w="$3" h="$4" ch="${5:- }" style="${6-}"
  local -i i j
  for (( j = 0; j < h; j++ )); do
    tui::put "$(( r + j ))" "${c}" "$(str::repeat "${ch}" "${w}")" "${style}"
  done
}

# @description Diff-render: emit only changed cells.
# @description Diff-рендер: выводить только изменившиеся клетки.
tui::render() {
  local -i r c
  local key new old newst oldst
  for (( r = 0; r < TUI_LINES; r++ )); do
    local row_out="" cur_style="" has_change=0
    # последняя выведенная колонка: несмежные изменения требуют перепозиции
    # last emitted column: non-contiguous changes need a new cursor jump
    local -i out_col=-2
    for (( c = 0; c < TUI_COLS; c++ )); do
      key="${r},${c}"
      new="${TUI_BUF[${key}]:- }"
      old="${TUI_LAST[${key}]:- }"
      newst="${TUI_BUF_STYLE[${key}]:-}"
      oldst="${TUI_LAST_STYLE[${key}]:-}"
      if [[ "${new}" != "${old}" || "${newst}" != "${oldst}" ]]; then
        if (( out_col != c - 1 )); then
          row_out+=$'\e['"$(( r + 1 ))"';'$(( c + 1 ))'H'
          has_change=1
        fi
        if [[ "${newst}" != "${cur_style}" ]]; then
          row_out+=$'\e[0m'"${newst}"
          cur_style="${newst}"
        fi
        row_out+="${new}"
        out_col="${c}"
      fi
    done
    (( has_change == 1 )) && printf '%s' "${row_out}"
  done
  # копия в last / snapshot
  TUI_LAST=()
  TUI_LAST_STYLE=()
  for key in "${!TUI_BUF[@]}"; do
    TUI_LAST["${key}"]="${TUI_BUF[${key}]}"
    TUI_LAST_STYLE["${key}"]="${TUI_BUF_STYLE[${key}]}"
  done
}

# ==========================================
# Key parsing / Парсер клавиш
# ==========================================

# @description Read one key (raw mode), fill TUI_KEY/TUI_KEY_CHAR.
# @description Прочитать клавишу (raw-режим), заполнить TUI_KEY.
tui::key_read() {
  TUI_KEY=""
  TUI_KEY_CHAR=""
  local k seq
  IFS= read -r -s -n1 k || k=""
  case "${k}" in
    $'\n'|"") TUI_KEY="ENTER" ;;
    $'\t')    TUI_KEY="TAB" ;;
    $'\x7f'|$'\b') TUI_KEY="BACKSPACE" ;;
    $'\e')
      # escape-последовательность / sequence
      IFS= read -r -s -n1 -t 0.05 k2 || k2=""
      if [[ -z "${k2}" ]]; then
        TUI_KEY="ESC"
        return 0
      fi
      case "${k2}" in
        '[')
          IFS= read -r -s -n1 -t 0.05 k3 || k3=""
          case "${k3}" in
            'A') TUI_KEY="UP" ;;
            'B') TUI_KEY="DOWN" ;;
            'C') TUI_KEY="RIGHT" ;;
            'D') TUI_KEY="LEFT" ;;
            'H') TUI_KEY="HOME" ;;
            'F') TUI_KEY="END" ;;
            'Z') TUI_KEY="BTAB" ;;
            'M') tui::__mouse_sgr; return 0 ;;
            '<') tui::__mouse_sgr; return 0 ;;
            '1'|'2'|'3'|'4'|'5'|'6'|'7'|'8')
              # модификатор: [1;5A = Ctrl+Up, [3~ = Delete, [5~ = PgUp
              IFS= read -r -s -n1 -t 0.05 k4 || k4=""
              local mod=""
              if [[ "${k4}" == ';' ]]; then
                IFS= read -r -s -n1 -t 0.05 mod || mod=""
                IFS= read -r -s -n1 -t 0.05 k5 || k5=""
                case "${mod}" in
                  5) mod="CTRL" ;;
                  3) mod="ALT" ;;
                  2) mod="SHIFT" ;;
                  *) mod="" ;;
                esac
                case "${k5}" in
                  'A') TUI_KEY="UP" ;;
                  'B') TUI_KEY="DOWN" ;;
                  'C') TUI_KEY="RIGHT" ;;
                  'D') TUI_KEY="LEFT" ;;
                  'H') TUI_KEY="HOME" ;;
                  'F') TUI_KEY="END" ;;
                  '~') TUI_KEY="SOME" ;;
                esac
                is::not_empty "${mod}" && TUI_KEY="${mod}+${TUI_KEY}"
              elif [[ "${k4}" == '~' ]]; then
                case "${k3}" in
                  1) TUI_KEY="HOME" ;;
                  2) TUI_KEY="INSERT" ;;
                  3) TUI_KEY="DELETE" ;;
                  4) TUI_KEY="END" ;;
                  5) TUI_KEY="PGUP" ;;
                  6) TUI_KEY="PGDN" ;;
                  7) TUI_KEY="HOME" ;;
                  8) TUI_KEY="END" ;;
                esac
              elif [[ "${k4}" =~ ^[0-9]$ ]]; then
                IFS= read -r -s -n1 -t 0.05 k5 || k5=""
                case "${k3}${k4}${k5}" in
                  '15~') TUI_KEY="F5" ;;
                  '17~') TUI_KEY="F6" ;;
                  '18~') TUI_KEY="F7" ;;
                  '19~') TUI_KEY="F8" ;;
                  '20~') TUI_KEY="F9" ;;
                  '21~') TUI_KEY="F10" ;;
                  '23~') TUI_KEY="F11" ;;
                  '24~') TUI_KEY="F12" ;;
                  *) TUI_KEY="UNKNOWN" ;;
                esac
              else
                TUI_KEY="UNKNOWN"
              fi
              ;;
            *) TUI_KEY="UNKNOWN" ;;
          esac
          ;;
        'O')
          IFS= read -r -s -n1 -t 0.05 k3 || k3=""
          case "${k3}" in
            'P') TUI_KEY="F1" ;;
            'Q') TUI_KEY="F2" ;;
            'R') TUI_KEY="F3" ;;
            'S') TUI_KEY="F4" ;;
            *) TUI_KEY="UNKNOWN" ;;
          esac
          ;;
        *)
          # Alt+<char> / Alt+символ
          TUI_KEY="ALT+${k2}"
          TUI_KEY_CHAR="${k2}"
          ;;
      esac
      ;;
    *)
      # обычный символ / plain char
      TUI_KEY="${k}"
      TUI_KEY_CHAR="${k}"
      ;;
  esac
  return 0
}

# @private
# @description Parse SGR mouse sequence: ESC[<b;x;yM / m.
# @description Разобрать SGR-последовательность мыши: ESC[<b;x;yM / m.
tui::__mouse_sgr() {
  # SGR: ESC[<b;x;yM / ESC[<b;x;ym. '<' уже прочитан как k3 / '<' already read as k3.
  # Хвостовой разделитель M/m поглощается самим read (-d) / trailing M/m consumed by read.
  local rest=""
  IFS= read -r -s -d 'M' -n 50 -t 0.1 rest || IFS= read -r -s -d 'm' -n 50 -t 0.1 rest || rest=""
  rest="${rest#<}"
  local b x y
  b="${rest%%;*}"
  rest="${rest#*;}"
  x="${rest%%;*}"
  y="${rest#*;}"
  y="${y%;*}"
  TUI_MOUSE_BUTTON="${b}"
  TUI_MOUSE_X="${x}"
  TUI_MOUSE_Y="${y}"
  TUI_KEY="MOUSE"
  return 0
}

# ==========================================
# Primitives / Примитивы
# ==========================================

# ==========================================
# Borders / Рамки
# ==========================================

# Текущий набор рамки / Current border set
declare -g TUI_BORDER_TL="╔" TUI_BORDER_TR="╗" TUI_BORDER_BL="╚" TUI_BORDER_BR="╝"
declare -g TUI_BORDER_H="═" TUI_BORDER_V="║"

# @description Select a border style / Выбрать стиль рамки.
#   double (default) — ╔═╗║╚╝   single — ┌─┐│└┘
#   rounded — ╭─╮│╰╯   dashed — ┌┄┐┆└┄┘
#   thick — ┏━┓┃┗━┛     none — без углов, только линии
# @param $1 style name / имя стиля
# @return 0 ok, 1 unknown
tui::border::set() {
  case "${1:-double}" in
    double)  TUI_BORDER_TL="╔" TUI_BORDER_TR="╗" TUI_BORDER_BL="╚" TUI_BORDER_BR="╝" TUI_BORDER_H="═" TUI_BORDER_V="║" ;;
    single)  TUI_BORDER_TL="┌" TUI_BORDER_TR="┐" TUI_BORDER_BL="└" TUI_BORDER_BR="┘" TUI_BORDER_H="─" TUI_BORDER_V="│" ;;
    rounded) TUI_BORDER_TL="╭" TUI_BORDER_TR="╮" TUI_BORDER_BL="╰" TUI_BORDER_BR="╯" TUI_BORDER_H="─" TUI_BORDER_V="│" ;;
    dashed)  TUI_BORDER_TL="┌" TUI_BORDER_TR="┐" TUI_BORDER_BL="└" TUI_BORDER_BR="┘" TUI_BORDER_H="┄" TUI_BORDER_V="┆" ;;
    thick)   TUI_BORDER_TL="┏" TUI_BORDER_TR="┓" TUI_BORDER_BL="┗" TUI_BORDER_BR="┛" TUI_BORDER_H="━" TUI_BORDER_V="┃" ;;
    none)    TUI_BORDER_TL="─" TUI_BORDER_TR="─" TUI_BORDER_BL="─" TUI_BORDER_BR="─" TUI_BORDER_H="─" TUI_BORDER_V="│" ;;
    *) return 1 ;;
  esac
  return 0
}

# @description Bordered box with optional title.
# @description Рамка с опциональным заголовком.
#   Стили: double/single/rounded/dashed/thick/none (tui::border::set).
#   Заголовок — «встроенный»: линия не прерывается, текст в середине.
#   Title is inline: the line is unbroken, text sits in the middle.
# @param $1 row, $2 col, $3 width, $4 height, $5 [title], $6 [style]
tui::box() {
  local -r r="$1" c="$2" w="$3" h="$4" title="${5-}" style="${6-}"
  local -i i
  local top shown_title="${title}"
  top="${TUI_BORDER_TL}${TUI_BORDER_H}"
  if is::not_empty "${title}"; then
    # длинный заголовок обрезаем, чтобы не уйти в отрицательный repeat
    # clamp long titles so the repeat count never goes negative
    local -i avail=$(( w - 5 ))
    (( avail < 0 )) && avail=0
    (( ${#title} > avail )) && shown_title="${title:0:${avail}}"
    top+=" ${shown_title} "
  else
    shown_title=""
  fi
  local -i fill=$(( w - ${#shown_title} - 5 ))
  (( fill < 0 )) && fill=0
  top+="$(str::repeat "${TUI_BORDER_H}" "${fill}")${TUI_BORDER_TR}"
  tui::put "${r}" "${c}" "${top}" "${style}"
  for (( i = 1; i < h - 1; i++ )); do
    tui::put "$(( r + i ))" "${c}" "${TUI_BORDER_V}" "${style}"
    tui::put "$(( r + i ))" "$(( c + w - 1 ))" "${TUI_BORDER_V}" "${style}"
  done
  tui::put "$(( r + h - 1 ))" "${c}" "${TUI_BORDER_BL}$(str::repeat "${TUI_BORDER_H}" $(( w - 2 )))${TUI_BORDER_BR}" "${style}"
}

# @description Text with clipping / Текст с обрезкой.
# @param $1 row, $2 col, $3 text, $4 [max width], $5 [style]
tui::text() {
  local -r r="$1" c="$2" text="$3"
  local -r maxw="${4:-${TUI_COLS}}"
  tui::put "${r}" "${c}" "${text:0:${maxw}}" "${5-}"
}

# @description Vertical scrollbar on the right edge.
# @description Вертикальный скроллбар у правого края.
# @param $1 row, $2 height, $3 total, $4 offset, $5 visible
tui::scrollbar() {
  local -r r="$1" h="$2" total="$3" offset="$4" visible="$5"
  (( total <= visible )) && return 0
  local -i thumb_h=$(( h * visible / total ))
  (( thumb_h < 1 )) && thumb_h=1
  local -i max_off=$(( total - visible ))
  local -i thumb_start=$(( offset * (h - thumb_h) / max_off ))
  local -i i
  local st
  st="$(tui::style cyan)"
  for (( i = 0; i < h; i++ )); do
    if (( i >= thumb_start && i < thumb_start + thumb_h )); then
      tui::put "$(( r + i ))" "${TUI_COLS}" "█" "${st}"
    else
      tui::put "$(( r + i ))" "${TUI_COLS}" "░" ""
    fi
  done
}

# ==========================================
# Widgets / Виджеты
# ==========================================

# @description Selectable list with viewport scrolling.
# @description Список с выбором и прокруткой.
# @param $1 row, $2 col, $3 width, $4 height
# @param $5 array name, $6 selected index, $7 [style], $8 [prefix-функция]
tui::list() {
  local -r r="$1" c="$2" w="$3" h="$4"
  local -r arr_name="$5" sel="$6" style="${7-}"
  local -rn arr="${arr_name}"
  local -i total=${#arr[@]}
  local -i offset=0
  (( sel < 0 )) && return 0
  (( total == 0 )) && return 0
  # viewport: выбранный всегда виден / keep selection visible
  if (( sel < offset )); then
    offset="${sel}"
  elif (( sel >= offset + h )); then
    offset=$(( sel - h + 1 ))
  fi
  local -i i idx
  local sel_style norm_style
  sel_style="$(tui::style bold reverse cyan)"
  norm_style="${style}"
  for (( i = 0; i < h; i++ )); do
    idx=$(( offset + i ))
    if (( idx < total )); then
      local row_text="${arr[${idx}]}"
      if (( idx == sel )); then
        tui::put "$(( r + i ))" "${c}" "▸ ${row_text:0:$(( w - 3 ))}" "${sel_style}"
      else
        tui::put "$(( r + i ))" "${c}" "  ${row_text:0:$(( w - 3 ))}" "${norm_style}"
      fi
    fi
  done
  tui::scrollbar "${r}" "${h}" "${total}" "${offset}" "${h}"
}

# @description Input field with block cursor.
# @description Поле ввода с блочным курсором.
# @param $1 row, $2 col, $3 width, $4 value, $5 [cursor pos], $6 [style]
tui::input() {
  local -r r="$1" c="$2" w="$3" value="$4" cur="${5:-${#4}}"
  local -r style="${6-}"
  local shown="${value:0:${w}}"
  tui::put "${r}" "${c}" "${shown}" "${style}"
  # блочный курсор / block cursor
  local -i cur_x=$(( c + cur ))
  (( cur_x >= c + w )) && cur_x=$(( c + w - 1 ))
  local ch="${TUI_BUF["$(( r - 1 )),$(( cur_x - 1 ))"]:- }"
  tui::put "${r}" "$(( cur_x ))" "${ch}" "$(tui::style reverse)"
}

# @description Modal confirm dialog drawn into the buffer.
# @description Модальное окно подтверждения в буфере.
# @param $1 title, $2 message, $3 [0=Yes selected, 1=No], $4 [w]
tui::confirm() {
  local -r title="$1" message="$2" sel="${3:-0}" w="${4:-52}"
  local -i h=7
  local -i bx=$(( (TUI_COLS - w) / 2 ))
  local -i by=$(( (TUI_LINES - h) / 2 ))
  local box_style
  box_style="$(tui::style bold cyan)"
  tui::box "${by}" "${bx}" "${w}" "${h}" "${title}" "${box_style}"
  tui::put "$(( by + 2 ))" "$(( bx + 2 ))" "${message:0:$(( w - 4 ))}"
  local yes_st no_st
  if (( sel == 0 )); then
    yes_st="$(tui::style reverse green)"
    no_st=""
  else
    yes_st=""
    no_st="$(tui::style reverse red)"
  fi
  tui::put "$(( by + 4 ))" "$(( bx + 4 ))" "[ Yes ]" "${yes_st}"
  tui::put "$(( by + 4 ))" "$(( bx + 14 ))" "[ No ]" "${no_st}"
}

# @description Progress bar / Индикатор прогресса.
# @param $1 row, $2 col, $3 width, $4 percent (0-100)
tui::progress() {
  local -r r="$1" c="$2" w="$3" pct="$4"
  local -i filled=$(( pct * (w - 8) / 100 ))
  local bar_style
  bar_style="$(tui::style green)"
  tui::put "${r}" "${c}" "[$(str::repeat "█" ${filled})$(str::repeat "░" $(( w - 8 - filled )))]" "${bar_style}"
  tui::put "${r}" "$(( c + w - 7 ))" "$(printf '%3d%%' "${pct}")" ""
}

# @description Spinner frame (braille) / Кадр спиннера (брайль).
# @param $1 row, $2 col, $3 frame index, $4 [style]
tui::spinner() {
  local -r r="$1" c="$2" frame="$3" style="${4-}"
  local -r frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  tui::put "${r}" "${c}" "${frames[${frame} % 10]}" "${style}"
}

# @description Vertical menu in a box / Вертикальное меню в рамке.
# @param $1 row, $2 col, $3 array name, $4 selected, $5 [title]
tui::menu() {
  local -r r="$1" c="$2" arr_name="$3" sel="$4" title="${5-}"
  local -rn arr="${arr_name}"
  local -i h=${#arr[@]}
  local w=20
  local item
  for item in "${arr[@]}"; do
    (( ${#item} + 4 > w )) && w=$(( ${#item} + 4 ))
  done
  local -i bx cw ch
  bx="${c}"; cw=$(( w + 4 )); ch=$(( h + 2 ))
  local box_style
  box_style="$(tui::style bold magenta)"
  tui::box "${r}" "${c}" "${cw}" "${ch}" "${title}" "${box_style}"
  local -i i
  for (( i = 0; i < h; i++ )); do
    if (( i == sel )); then
      tui::put "$(( r + 1 + i ))" "$(( c + 2 ))" "▸ ${arr[${i}]}" "$(tui::style reverse)"
    else
      tui::put "$(( r + 1 + i ))" "$(( c + 2 ))" "  ${arr[${i}]}" ""
    fi
  done
}

# ==========================================
# Modal stack / Стек модальных окон
# ==========================================

# @description Open a modal (draw fn called after the base frame).
# @description Открыть модальное окно (draw-функция вызывается после базы).
# @param $1 name, $2 draw function name
tui::modal::open() {
  TUI_MODAL_DRAW["${1}"]="${2}"
  TUI_MODAL_STACK+=("${1}")
}

# @description Close the top modal / Закрыть верхнее модальное окно.
tui::modal::close() {
  local name
  if is::not_empty "${1-}"; then
    name="$1"
    # удалить конкретное / remove specific
    local -a new_stack=()
    local n
    for n in "${TUI_MODAL_STACK[@]}"; do
      [[ "${n}" != "${name}" ]] && new_stack+=("${n}")
    done
    TUI_MODAL_STACK=("${new_stack[@]}")
    unset "TUI_MODAL_DRAW[${name}]"
  elif (( ${#TUI_MODAL_STACK[@]} > 0 )); then
    name="${TUI_MODAL_STACK[-1]}"
    TUI_MODAL_STACK=("${TUI_MODAL_STACK[@]:0:${#TUI_MODAL_STACK[@]}-1}")
    unset "TUI_MODAL_DRAW[${name}]"
  fi
}

# @description Name of the top modal (empty = none).
# @description Имя верхней модалки (пусто = нет).
tui::modal::top() {
  if (( ${#TUI_MODAL_STACK[@]} > 0 )); then
    printf '%s\n' "${TUI_MODAL_STACK[-1]}"
  fi
  return 0
}

# @description Draw all modals in order (top last).
# @description Нарисовать все модалки по порядку (верхняя последней).
tui::modal::draw_all() {
  local name fn
  for name in "${TUI_MODAL_STACK[@]}"; do
    fn="${TUI_MODAL_DRAW[${name}]:-}"
    is::function "${fn}" && "${fn}"
  done
}

# ==========================================
# Helpers / Хелперы
# ==========================================

# @description Centered box coordinates / Центрированные координаты.
# @param $1 width, $2 height → TUI_CENTER_X, TUI_CENTER_Y
tui::center() {
  local -r w="$1" h="$2"
  TUI_CENTER_X=$(( (TUI_COLS - w) / 2 ))
  TUI_CENTER_Y=$(( (TUI_LINES - h) / 2 ))
}

# @description Status bar at the bottom / Строка статуса внизу.
# @param $1 text, $2 [style]
tui::statusbar() {
  local -r text="$1" style="${2-}"
  local full
  full="${text:0:${TUI_COLS}}"
  tui::fill "${TUI_LINES}" 1 "${TUI_COLS}" 1 " " "${style}"
  tui::put "${TUI_LINES}" 1 "${full}" "${style}"
}

# @description Title bar at the top / Заголовок сверху.
tui::titlebar() {
  local -r text="$1" style="${2-}"
  tui::fill 1 1 "${TUI_COLS}" 1 " " "${style}"
  tui::put 1 1 "${text:0:${TUI_COLS}}" "${style}"
}