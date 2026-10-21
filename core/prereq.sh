#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: имена bs_guard/bs_guard_loaded/bs_source_relative, без [[ ]], массивов и ${x^^}; имена bs::* — псевдонимы только в bash/zsh / valid POSIX sh: bs_guard/bs_guard_loaded/bs_source_relative, no [[ ]], arrays or ${x^^}; the bs::* names are aliases in bash/zsh only
# @tier core — builtins only (tr only for a lower-case module name); works everywhere
# @tier core — только builtin'ы (tr лишь для имени модуля в нижнем регистре); работает везде
#
# core/prereq.sh — базовые примитивы ядра BS, доступные априори
# core/prereq.sh — core primitives available a priori to all BS modules
#
# Этот файл не имеет зависимостей, кроме реестра bootstrap/shell.sh, и
# подключается напрямую (raw source).
# It has no dependencies except the registry bootstrap/shell.sh and is sourced
# directly (raw source).
#
# Pre-kernel helpers (bs::shell::*, bs::script_dir, PATH tweak) live in
# bootstrap/bs.sh, which is sourced before this file (see bootstrap/init.sh
# and bootstrap/loader.sh).
# Pre-kernel хелперы (bs::shell::*, bs::script_dir, PATH-твик) живут в
# bootstrap/bs.sh, который подключается раньше этого файла (см.
# bootstrap/init.sh и bootstrap/loader.sh).
#
# ИМЕНА / NAMES
#   Real functions: bs_guard, bs_guard_loaded, bs_source_relative (dash rejects
#   "a::b"). In bash and zsh they are also available as bs::guard,
#   bs::guard_loaded, bs::source_relative — every existing caller keeps working.
#   Настоящие функции: bs_guard, bs_guard_loaded, bs_source_relative (dash не
#   принимает "a::b"). В bash и zsh они же доступны как bs::guard,
#   bs::guard_loaded, bs::source_relative — все прежние вызовы работают.

# Реестр оболочек даёт bs_shell_alias, bs_shell_readonly и bs_shell_family; его
# подключает bs.sh
# The shell registry gives bs_shell_alias, bs_shell_readonly and bs_shell_family;
# bs.sh sources it
if ! command -v bs_shell_readonly >/dev/null 2>&1; then
  printf '%s\n' "BS: core/prereq.sh: bootstrap/shell.sh is not loaded / не загружен bootstrap/shell.sh" >&2
  return 1
fi

# Self-guard via raw idiom: bs_guard is defined here, so cannot use it yet.
# Простой self-guard: bs_guard определён здесь же, пользоваться им ещё нельзя.
[ -z "${__PREREQ_SOURCED:-}" ] || return 0
__PREREQ_SOURCED=1
bs_shell_readonly __PREREQ_SOURCED
# @description Compute the sentinel variable name of a module (__<NAME>_SOURCED) into
#   __bs_g_var (no subshell: it runs for every module).
# @description Вычислить имя переменной-метки модуля (__<ИМЯ>_SOURCED) в __bs_g_var
#   (без подоболочки: вызывается для каждого модуля).
# @param $1 Module name (without __ and _SOURCED), a-z A-Z 0-9 _ / Имя модуля
# @returns 0 ok (name in __bs_g_var); 2 the name is not a valid identifier part
bs_guard__var() {
  __bs_gv_name=${1:?Module name required}
  case "$__bs_gv_name" in
    *[!A-Z0-9_]*) __bs_gv_name=$(printf '%s' "$__bs_gv_name" | tr '[:lower:]' '[:upper:]') ;;
  esac
  case "$__bs_gv_name" in
    ''|*[!A-Z0-9_]*) return 2 ;;
  esac
  __bs_g_var=__${__bs_gv_name}_SOURCED
}

# @description Check-and-set module loaded mark.
# @param $1 Module name (without __ and _SOURCED).
# @returns 0 first load; 1 already loaded — caller should return 0; 2 bad name.
bs_guard() {
  bs_guard__var "$@" || return 2
  eval "[ -z \"\${${__bs_g_var}:-}\" ]" || return 1
  eval "${__bs_g_var}=1"
  bs_shell_readonly "$__bs_g_var"
  return 0
}

# @description Query whether a module is loaded.
# @param $1 Module name.
# @returns 0 loaded; 1 not loaded.
bs_guard_loaded() {
  bs_guard__var "$@" || return 1
  eval "[ -n \"\${${__bs_g_var}:-}\" ]"
}

# @description Source one file, keeping BS_CURRENT_FILE pointed at it meanwhile.
# @description Подключить один файл; на это время BS_CURRENT_FILE указывает на него.
# @param $1 Value to restore into BS_CURRENT_FILE afterwards / Что вернуть в BS_CURRENT_FILE
# @param $2 File to source / Подключаемый файл
bs_source__one() {
  BS_CURRENT_FILE=$2
  # shellcheck disable=SC1090
  . "$2"
  __bs_so_rc=$?
  BS_CURRENT_FILE=$1
  return "$__bs_so_rc"
}

# @description Source files relative to the directory of a given file.
# @description Подключить файлы относительно каталога заданного файла.
# @param $1 File whose directory is the base / Файл, чей каталог — база
# @param $@ Relative file paths / Относительные пути файлов
# @returns Status of the last file / Статус последнего файла
bs_source_relative_from() {
  case "${1:?base file required}" in
    */*) __bs_sr_d=${1%/*} ;;
    *)   __bs_sr_d=. ;;
  esac
  shift
  # Полные пути в позиционные параметры: вложенные вызовы не портят состояние
  # Full paths into the positional parameters: nested calls cannot clobber state
  __bs_sr_n=$#
  while [ "$__bs_sr_n" -gt 0 ]; do
    set -- "$@" "${__bs_sr_d}/$1"
    shift
    __bs_sr_n=$((__bs_sr_n - 1))
  done
  __bs_sr_rc=0
  for __bs_sr_f in "$@"; do
    bs_source__one "${BS_CURRENT_FILE:-}" "$__bs_sr_f"
    __bs_sr_rc=$?
  done
  return "$__bs_sr_rc"
}

# @description Source files relative to the caller's directory. The caller's file
#   is the one the loader is sourcing now (BS_CURRENT_FILE); bash additionally
#   reads it from the call stack, so a call from a function works too.
# @description Подключить файлы относительно каталога вызывающего. Файл вызывающего —
#   тот, что сейчас подключает загрузчик (BS_CURRENT_FILE); bash дополнительно
#   берёт его из стека вызовов, поэтому вызов из функции тоже работает.
# @param $@ Relative file paths from the caller's directory.
case "$(bs_shell_family)" in
  bash)
    # Отдельная ветка bash: вызывающий — кадр стека 1 (обёртки между нет); без
    # bootstrap/bs.sh (нет bs::stack_file) — BS_CURRENT_FILE, как в других оболочках
    # A bash branch of its own: the caller is stack frame 1 (no wrapper between);
    # without bootstrap/bs.sh (no bs::stack_file) — BS_CURRENT_FILE, as in other shells
    # Стек через bs::stack_file_to (без подоболочки): старый $(bs::stack_file 1)
    # стоил форк на каждую зависимость. Без bootstrap/bs.sh — BS_CURRENT_FILE.
    # The stack via bs::stack_file_to (no subshell): the old $(bs::stack_file 1)
    # cost a fork per dependency. Without bootstrap/bs.sh — BS_CURRENT_FILE.
    if command -v bs::stack_file_to >/dev/null 2>&1; then
      eval 'bs_source_relative() { bs::stack_file_to __bs_sr_caller 1; bs_source_relative_from "${__bs_sr_caller:-${BS_CURRENT_FILE:-}}" "$@"; }'
      eval 'bs::source_relative() { bs::stack_file_to __bs_sr_caller 1; bs_source_relative_from "${__bs_sr_caller:-${BS_CURRENT_FILE:-}}" "$@"; }'
    else
      eval 'bs_source_relative() { bs_source_relative_from "${BS_CURRENT_FILE:-}" "$@"; }'
      eval 'bs::source_relative() { bs_source_relative_from "${BS_CURRENT_FILE:-}" "$@"; }'
    fi
    ;;
  *)
    bs_source_relative() {
      bs_source_relative_from "${BS_CURRENT_FILE:?BS_CURRENT_FILE is not set: source through the loader / не задан BS_CURRENT_FILE: подключайте через загрузчик}" "$@"
    }
    bs_shell_alias bs_source_relative bs::source_relative
    ;;
esac

bs_shell_alias bs_guard bs::guard
bs_shell_alias bs_guard_loaded bs::guard_loaded
