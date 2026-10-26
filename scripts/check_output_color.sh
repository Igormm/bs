#!/bin/sh
# shellcheck shell=sh
# @shell posix — grep/find/awk over text; no bash constructs / grep/find/awk по тексту, без конструкций bash
# @tier dev — a developer inventory, not part of the runtime / инвентарь разработчика, не часть рантайма
#
# scripts/check_output_color.sh — найти команды вывода и показать те, что обходят
# helpers цвета/лога/presentation. Это инвентарь для глаз, а не гейт CI.
# scripts/check_output_color.sh — find output commands and show the ones that
# bypass the colour/log/presentation helpers. An inventory for the eyes, not a
# CI gate.
#
# Использование / Usage:
#   sh scripts/check_output_color.sh                  # bootstrap/cli.sh + lib/ (без движков)
#   sh scripts/check_output_color.sh --list           # + каждая неокрашенная команда / every plain command
#   sh scripts/check_output_color.sh --all lib        # включая движки цвета/лога / including the engines
#   sh scripts/check_output_color.sh bootstrap/cli.sh lib/io/files.sh
#
# Что считается: команды printf/echo/print/printn/eprint/eprintn/tty_print в
# начале логической строки (продолжения через `\` склеиваются), вне heredoc.
# `printf -v` — не вывод, а присваивание, поэтому в счётчик plain не идёт.
# What counts: printf/echo/print/printn/eprint/eprintn/tty_print at the start of
# a logical line (backslash continuations joined), outside heredocs. `printf -v`
# assigns a variable instead of printing, so it is not counted as plain.

set -eu

list=0
all=0
explicit=0

usage() {
  printf '%s\n' \
    'Usage: scripts/check_output_color.sh [--list] [--all] [PATH...]' \
    '' \
    '  --list  print every plain output command, not just per-file counts' \
    '  --all   scan the colour/log/stream engines too (skipped by default)' \
    '' \
    'Default paths: bootstrap/cli.sh and lib/. A directory is scanned recursively.' \
    'A path given on the command line is always scanned, even an engine.'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --list) list=1 ;;
    --all)  all=1 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    --*) usage >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done

if [ "$#" -gt 0 ]; then
  explicit=1
fi

is_engine() {
  case "$1" in
    core/const.sh|core/logger.sh|lib/io/streams.sh|lib/ui/presentation.sh|lib/ui/wizard.sh)
      return 0 ;;
    lib/tui/*) return 0 ;;
  esac
  return 1
}

scan_file() {
  [ -f "$1" ] || return 0
  if [ "${explicit}" -eq 0 ] && [ "${all}" -eq 0 ] && is_engine "$1"; then
    return 0
  fi
  awk -v file="$1" -v list="${list}" '
    function flush(   c) {
      if (cmd == "") return
      c = cmd
      cmd = ""
      total++
      if (c ~ /printf[ \t]+-v[ \t]/) { internal++; return }
      if (index(c, "BS_CLI_INFO_NO_COLOR") > 0) { off++; return }
      if (index(c, "bs_cli_paint") > 0 || index(c, "bs_log_") > 0 ||
          index(c, "presentation::") > 0 || index(c, "tui::") > 0 ||
          index(c, "wiz::") > 0 || index(c, "COLOR_") > 0 ||
          index(c, "PRESENTATION_") > 0 || index(c, "bs_error_exit") > 0 ||
          index(c, "bs_cli_die") > 0 || index(c, "$'\''\\033'\''") > 0 ||
          index(c, "\\033[") > 0) {
        coloured++
        return
      }
      plain++
      if (list) printf "  plain %s:%d: %s\n", file, start, substr(c, 1, 160)
    }
    function heredoc_tag(s,   t) {
      if (match(s, /<<-?[ \t]*['\''"]?[A-Za-z_][A-Za-z0-9_]*/)) {
        t = substr(s, RSTART, RLENGTH)
        sub(/^<<-?[ \t]*/, "", t)
        gsub(/['\''"]/, "", t)
        return t
      }
      return ""
    }
    {
      if (hd != "") {
        if ($0 == hd) hd = ""
        next
      }
      if (cmd != "") {
        cmd = cmd " " $0
        if ($0 ~ /\\[ \t]*$/) next
        flush()
        next
      }
      if ($0 ~ /^[ \t]*(printf|echo|printn?|eprintn?|tty_print)[ \t]/) {
        cmd = $0
        start = FNR
        if ($0 ~ /\\[ \t]*$/) next
        flush()
        next
      }
      tag = heredoc_tag($0)
      if (tag != "") hd = tag
    }
    END {
      flush()
      if (total == 0) exit
      printf "%s: %d output, %d coloured, %d plain", file, total, coloured, plain
      if (internal) printf ", %d internal", internal
      if (off) printf ", %d deliberately plain", off
      printf "\n"
    }
  ' "$1"
}

scan_path() {
  [ -e "$1" ] || { printf 'check_output_color: no such path: %s\n' "$1" >&2; exit 2; }
  if [ -d "$1" ]; then
    find "$1" -type f -name '*.sh' | sort | while IFS= read -r f; do
      scan_file "$f"
    done
  else
    scan_file "$1"
  fi
}

if [ "${explicit}" -eq 1 ]; then
  for path in "$@"; do
    scan_path "${path}"
  done
else
  scan_file "bootstrap/cli.sh"
  scan_path "lib"
fi

if [ "${list}" -eq 1 ]; then
  exit 0
fi
printf '\n%s\n' 'plain = no colour/log/presentation helper; review each one by hand.'
