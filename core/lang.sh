#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: только test, case и command -v / valid POSIX sh: test, case and command -v only
# @tier core — builtins only; works everywhere
# @tier core — только builtin'ы; работает везде
#
# core/lang.sh — предикаты is::* («проверки для людей»)
# core/lang.sh — the is::* predicates ("tests for humans")
#
# Дружелюбные замены для тестовых идиом: не нужно помнить, что -n значит «непусто», а -f —
# «обычный файл». Остальные языковые примитивы bash (интроспекция, str::*, arr::*, map::*,
# bs::slice) живут в lib/compat/lang.sh: они работают с настоящими массивами bash.
# Friendly replacements for test idioms: no need to remember that -n means "non-empty" and
# -f means "regular file". The other bash language primitives (introspection, str::*, arr::*,
# map::*, bs::slice) live in lib/compat/lang.sh: they work on real bash arrays.
#
# ИМЕНА / NAMES
#   Real functions: bs_is_empty, bs_is_not_empty, bs_is_exists, bs_is_file, bs_is_dir,
#   bs_is_symlink, bs_is_file_not_empty, bs_is_executable, bs_is_readable, bs_is_writable,
#   bs_is_number, bs_is_command; in bash and zsh also is::* (the old names, aliases).
#   is::function and is::command stay in lib/compat/lang.sh: only bash tells a function from a command,
#   and is::command keeps calling utils::has by name, so that tests can replace it.
#   Настоящие функции — bs_is_*; в bash и zsh — ещё и is::* (прежние имена, псевдонимы).
#   is::function и is::command остаются в lib/compat/lang.sh: функцию от команды отличает только bash,
#   а is::command вызывает utils::has по имени, чтобы тесты могли его подменить.

bs_guard LANG || return 0

# @description Predicate: string is empty / Строка пуста. Replaces: [ -z "$s" ]
bs_is_empty() {
  [ -z "${1-}" ]
}

# @description Predicate: string is not empty / Строка непуста. Replaces: [ -n "$s" ]
bs_is_not_empty() {
  [ -n "${1-}" ]
}

# @description Predicate: path exists / Путь существует. Replaces: [ -e "$p" ]
bs_is_exists() {
  [ -e "${1-}" ]
}

# @description Predicate: regular file / Обычный файл. Replaces: [ -f "$p" ]
bs_is_file() {
  [ -f "${1-}" ]
}

# @description Predicate: directory / Каталог. Replaces: [ -d "$p" ]
bs_is_dir() {
  [ -d "${1-}" ]
}

# @description Predicate: symbolic link / Симлинк. Replaces: [ -L "$p" ]
bs_is_symlink() {
  [ -L "${1-}" ]
}

# @description Predicate: file is not empty / Файл непустой. Replaces: [ -s "$p" ]
bs_is_file_not_empty() {
  [ -s "${1-}" ]
}

# @description Predicate: executable / Исполняемый. Replaces: [ -x "$p" ]
bs_is_executable() {
  [ -x "${1-}" ]
}

# @description Predicate: readable / Доступен на чтение. Replaces: [ -r "$p" ]
bs_is_readable() {
  [ -r "${1-}" ]
}

# @description Predicate: writable / Доступен на запись. Replaces: [ -w "$p" ]
bs_is_writable() {
  [ -w "${1-}" ]
}

# @description Predicate: string is a non-negative integer (digits only, at least one).
# @description Предикат: строка — целое число без знака (только цифры, хотя бы одна).
bs_is_number() {
  case "${1-}" in
    '' | *[!0-9]*) return 1 ;;
  esac
  return 0
}

# @description Predicate: command is available / Команда доступна.
#   Alias of bs_utils_has. Replaces: command -v cmd >/dev/null 2>&1
bs_is_command() {
  bs_utils_has "${1:?command name required}"
}

bs_shell_alias bs_is_empty is::empty
bs_shell_alias bs_is_not_empty is::not_empty
bs_shell_alias bs_is_exists is::exists
bs_shell_alias bs_is_file is::file
bs_shell_alias bs_is_dir is::dir
bs_shell_alias bs_is_symlink is::symlink
bs_shell_alias bs_is_file_not_empty is::file_not_empty
bs_shell_alias bs_is_executable is::executable
bs_shell_alias bs_is_readable is::readable
bs_shell_alias bs_is_writable is::writable
bs_shell_alias bs_is_number is::number
