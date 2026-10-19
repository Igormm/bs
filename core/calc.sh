#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: redirect'ы, case и подстановки параметров; log::* берётся, только если загружен логгер / valid POSIX sh: redirects, case and parameter expansion; log::* is used only if the logger is loaded
# @tier core — builtins and dc; works everywhere
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

# ИМЕНА / NAMES
#   Real functions: bs_calc_help, bs_calc_autop, bs_calc_eval, bs_calc_interactive, bs_calc_main;
#   in bash and zsh also calc::* (the old names, used by the bs command).
#   Настоящие функции: bs_calc_help, bs_calc_autop, bs_calc_eval, bs_calc_interactive, bs_calc_main;
#   в bash и zsh — ещё и calc::* (прежние имена, их зовёт команда bs).

# Source Guard / Защита от повторной загрузки
bs_guard CORE_CALC || return 0

# Dependencies / Зависимости
bs_source_relative "msg.sh"

# @description Показать справку / Show help
bs_calc_help() {
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
bs_calc_autop() {
  case "${1:-}" in
    *"#"*)
      printf '%s\n' "${1:-}"
      return 0 ;;
  esac
  __bs_calc_last=${1:-}
  __bs_calc_last=${__bs_calc_last##* }
  case "$__bs_calc_last" in
    p|n|P|f) printf '%s\n' "${1:-}" ;;
    *) printf '%s p\n' "${1:-}" ;;
  esac
}

# @description Evaluate an RPN expression / Вычислить RPN-выражение
# @param $1 {string} RPN expression / RPN-выражение
# @stdout результат / result
# @return код возврата dc / dc exit status
# @example
#   bs calc '2 3 4 * +'
bs_calc_eval() {
  __bs_calc_expr=${1:?expression required}
  __bs_calc_code=$(bs_calc_autop "$__bs_calc_expr")
  printf '%s\n' "$__bs_calc_code" | dc
}

# @description Interactive mode / Интерактивный режим
#   Each new line is appended to the session and the whole session is
#   re-evaluated, so the stack persists between lines.
#   Каждая новая строка добавляется к сессии, и вся сессия пересчитывается
#   заново — стек сохраняется между строками.
bs_calc_interactive() {
  __bs_calc_session=''
  printf 'BS calc — RPN on dc. :q / Ctrl-D — exit. Top of stack is printed.\n'
  while true; do
    # приглашение — только на терминале, как у read -p / the prompt only on a terminal, like read -p
    if [ -t 0 ]; then printf 'dc> ' >&2; fi
    if ! read -r __bs_calc_line; then
      printf '\n'
      return 0
    fi
    case "$__bs_calc_line" in
      :q|:quit|:exit|exit) return 0 ;;
    esac
    [ -n "$__bs_calc_line" ] || continue
    __bs_calc_session="${__bs_calc_session}${__bs_calc_line}
"
    if ! printf '%s\n' "$(bs_calc_autop "$__bs_calc_session")" | dc; then
      bs_msg_warn "calc: dc failed (see error above)"
    fi
  done
}

# @description Entry point / Точка входа
bs_calc_main() {
  case "${1:-}" in
    -h|--help)
      bs_calc_help
      return 0 ;;
  esac

  if ! command -v dc >/dev/null 2>&1; then
    bs_msg_error "calc: dc not found — install bc/dc (part of every Linux distribution)"
    return 1
  fi

  if [ $# -ge 1 ]; then
    bs_calc_eval "$*"
    return $?
  fi

  bs_calc_interactive
}

bs_shell_alias bs_calc_help calc::help
bs_shell_alias bs_calc_autop calc::__autop
bs_shell_alias bs_calc_eval calc::eval
bs_shell_alias bs_calc_interactive calc::interactive
bs_shell_alias bs_calc_main calc::main
