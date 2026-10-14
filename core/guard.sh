#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: только проверка и подключение core/prereq.sh, без [[ ]], declare -f и BASH_* / valid POSIX sh: only a check and a source of core/prereq.sh, no [[ ]], declare -f or BASH_*
# @tier core — builtins only; works everywhere
# @tier core — только builtin'ы; работает везде
#
# core/guard.sh — compatibility alias for core/prereq.sh
# core/guard.sh — обратносовместимая обёртка над core/prereq.sh
#
# Historically this file defined bs::guard, bs::guard_loaded and
# bs::source_relative. They have been moved to core/prereq.sh so that
# core prerequisites are loaded from a file whose only job is to be
# the a-priori core machinery.
#
# @depends (none)

# Реестр оболочек (bootstrap/shell.sh) даёт bs_shell_readonly; его подключает bs.sh
# The shell registry (bootstrap/shell.sh) gives bs_shell_readonly; bs.sh sources it
if ! command -v bs_shell_readonly >/dev/null 2>&1; then
  printf '%s\n' "BS: core/guard.sh: bootstrap/shell.sh is not loaded / не загружен bootstrap/shell.sh" >&2
  return 1
fi

# Self-guard: prevent double-source even though we just re-export prereq.
[ -z "${__GUARD_SOURCED:-}" ] || return 0
__GUARD_SOURCED=1
bs_shell_readonly __GUARD_SOURCED

# Load core prerequisites if not already available. The directory is BS_ROOT/core
# (a sourced file does not find its own path); without BS_ROOT — the directory of
# the file the loader is sourcing (BS_CURRENT_FILE).
# Подключить базовые примитивы, если их ещё нет. Каталог — BS_ROOT/core (подключаемый
# файл свой путь не определяет); без BS_ROOT — каталог файла, который подключает
# загрузчик (BS_CURRENT_FILE).
if ! command -v bs_guard >/dev/null 2>&1; then
  if [ -n "${BS_ROOT:-}" ]; then
    __bs_gd_dir=${BS_ROOT}/core
  elif [ -n "${BS_CURRENT_FILE:-}" ]; then
    __bs_gd_dir=${BS_CURRENT_FILE%/*}
  else
    printf '%s\n' "BS: core/guard.sh: neither BS_ROOT nor BS_CURRENT_FILE is set / не заданы ни BS_ROOT, ни BS_CURRENT_FILE" >&2
    return 1
  fi
  # shellcheck disable=SC1091
  . "${__bs_gd_dir}/prereq.sh"
fi
