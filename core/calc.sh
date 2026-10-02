#!/usr/bin/env bash
#
# core/calc.sh — RPN calculator on dc / RPN-калькулятор на dc
# Обратная польская нотация: числа кладутся на стек, операторы берут их
# оттуда и кладут результат. Верх стека печатается автоматически.
# Reverse Polish notation: numbers go on the stack, operators pop and push
# the result. The top of the stack is printed automatically.
#
# Usage / Использование:
#   bs calc [expression]
#   bs calc
#   bs calc --help
#
# Примеры / Examples:
#   bs calc '2 3 4 * +'       → 14
#   bs calc '10k 355 113 /'   → 3.1415929203  (точность 10 / scale 10)

# @depends core/lang, core/utils, core/logger

# Source Guard / Защита от повторной загрузки
bs::guard "CORE_CALC" || return 0

# @description Показать справку / Show help
calc::help() {
  cat <<HELP
BS calc — RPN calculator on dc / RPN-калькулятор на dc

Usage / Использование:
  bs calc [expression]     Evaluate one expression / вычислить выражение
  bs calc                  Interactive mode / интерактивный режим
  bs calc --help           Show this help / показать справку

The top of the stack is printed automatically unless the expression ends
with a print command (p, n, P, f) or contains a # comment.
Верх стека печатается автоматически, если выражение не заканчивается
командой печати (p, n, P, f) и не содержит комментарий #.

Examples / Примеры:
  bs calc '2 3 4 * +'       → 14
  bs calc '10k 355 113 /'   → 3.1415929203  (scale 10 / точность 10)
  bs calc '2 3 + p'         → 5  (явная печать / explicit print)

Interactive mode: the stack persists between lines (the whole session is
re-evaluated each time). :q / Ctrl-D — exit.
Интерактивный режим: стек живёт между строками (сессия пересчитывается
каждый раз). :q / Ctrl-D — выход.
HELP
}

# @private
# @description Append a print command p unless the expression prints itself
# @description Добавить команду печати p, если выражение её не содержит
calc::__autop() {
  local -r expr="${1:-}"
  if [[ "${expr}" == *"#"* ]]; then
    printf '%s\n' "${expr}"
    return 0
  fi
  local -r last="${expr##* }"
  case "${last}" in
    p|n|P|f) printf '%s\n' "${expr}" ;;
    *) printf '%s p\n' "${expr}" ;;
  esac
}

# @description Evaluate an RPN expression / Вычислить RPN-выражение
# @param $1 {string} RPN expression / RPN-выражение
# @stdout результат / result
# @return код возврата dc / dc exit status
# @example
#   bs calc '2 3 4 * +'
calc::eval() {
  local -r expr="${1:?expression required}"
  local code
  code="$(calc::__autop "${expr}")"
  printf '%s\n' "${code}" | dc
}

# @description Interactive mode / Интерактивный режим
#   Each new line is appended to the session and the whole session is
#   re-evaluated, so the stack persists between lines.
#   Каждая новая строка добавляется к сессии, и вся сессия пересчитывается
#   заново — стек сохраняется между строками.
calc::interactive() {
  local session="" line=""
  printf 'BS calc — RPN on dc. :q / Ctrl-D — exit. Top of stack is printed.\n'
  while true; do
    if ! read -r -p 'dc> ' line; then
      printf '\n'
      return 0
    fi
    case "${line}" in
      :q|:quit|:exit|exit) return 0 ;;
    esac
    if is::empty "${line}"; then
      continue
    fi
    session+="${line}"$'\n'
    if ! printf '%s\n' "$(calc::__autop "${session}")" | dc; then
      log::warn "calc: dc failed (see error above)"
    fi
  done
}

# @description Entry point / Точка входа
calc::main() {
  case "${1:-}" in
    -h|--help)
      calc::help
      return 0 ;;
  esac

  if ! is::command dc; then
    log::error "calc: dc not found — install bc/dc (part of every Linux distribution)"
    return 1
  fi

  if [[ $# -ge 1 ]]; then
    calc::eval "$*"
    return $?
  fi

  calc::interactive
}