#!/bin/sh
# shellcheck shell=sh
#
# bootstrap/trampoline.sh — re-run an entry point in a capable bash, or explain
# what to install
# bootstrap/trampoline.sh — перезапустить точку входа в подходящем bash или
# объяснить, что установить
#
# @shell posix — valid POSIX sh; runs in dash, ash/busybox, zsh, ksh, bash
# @shell posix — валидный POSIX sh; работает в dash, ash/busybox, zsh, ksh, bash
# @tier core — no tools beyond builtins and readlink; works everywhere
# @tier core — только builtin'ы и readlink; работает везде
#
# WHY / ЗАЧЕМ
#   `sh install.sh`, `dash ./bs version`, `zsh ./install.sh`, bash 3.2 or bash
#   started as `sh` (POSIX mode) all run BS entry points in a shell that cannot
#   parse them: the user sees "Bad substitution" or "[[: not found". Every
#   entry point starts with a short POSIX prologue that sources this file when
#   the interpreter is not bash 4+ in normal mode. Here a capable bash is
#   searched and the entry point is re-run with the same arguments — except a
#   command that bootstrap/cli.sh already serves: it stays in the current shell.
#   `sh install.sh`, `dash ./bs version`, `zsh ./install.sh`, bash 3.2 или
#   bash, запущенный как `sh` (режим POSIX), исполняют точки входа BS в
#   оболочке, которая их не разберёт: пользователь видит «Bad substitution»
#   или «[[: not found». Каждая точка входа начинается с короткого
#   POSIX-пролога, который подключает этот файл, если интерпретатор — не
#   bash 4+ в обычном режиме. Здесь ищется подходящий bash, и точка входа
#   запускается заново с теми же аргументами — кроме команды, которую уже
#   обслуживает bootstrap/cli.sh: она остаётся в текущей оболочке.
#
# CONTRACT / КОНТРАКТ
#   Input: the caller is a script FILE (${__bs_s} is its path: zsh changes $0
#   inside a sourced file), the positional parameters are the caller's,
#   ${__bs_p} is the directory of the entry point (it holds bootstrap/).
#   Output: a bash command — exec into bash (does not return) or exit 1;
#   a POSIX command of an entry point that sets BS_POSIX_CMDS — return 0 and
#   let the entry point run in the current shell.
#   Вход: вызывающий — ФАЙЛ-скрипт (${__bs_s} — его путь: zsh меняет $0
#   внутри подключаемого файла), позиционные параметры — вызывающего,
#   ${__bs_p} — каталог точки входа (в нём bootstrap/). Выход: bash-команда —
#   exec в bash (не возвращается) либо exit 1; POSIX-команда точки входа,
#   которая ставит BS_POSIX_CMDS, — return 0, точка входа остаётся в текущей
#   оболочке.
#   Override / Переопределение: BS_HOST_BASH=/path/to/bash

__bs_t_self=${__bs_s:-$0}

# Подключили из интерактивной оболочки, а не запустили файл — exec нечего.
# $0 может указывать и на бинарник самой оболочки (`dash -c ". файл"`), поэтому
# файл должен начинаться с "#!" — как все точки входа BS.
# The file was sourced into an interactive shell, not run — nothing to exec.
# $0 can also point to the shell binary itself (`dash -c ". file"`), so the
# file must start with "#!" — like every BS entry point.
__bs_t_first=''
[ -f "$__bs_t_self" ] && __bs_t_first=$(head -n 1 -- "$__bs_t_self" 2>/dev/null | head -c 2)
if [ "$__bs_t_first" != '#!' ]; then
  printf '%s\n' "BS: этот файл нужно запускать как программу, а не подключать через source / . в оболочке" \
    "BS: run this file as a program instead of sourcing it into the shell" >&2
  # shellcheck disable=SC2317  # запасной exit, если return вне источника
  return 1 2>/dev/null || exit 1
fi

# Защита от зацикливания: повторный заход после exec означает сбой выбора bash
# Loop guard: coming back here after an exec means the bash choice failed
if [ -n "${__BS_TRAMPOLINE:-}" ]; then
  printf '%s\n' "BS: перезапуск в bash не помог (зацикливание), остановлено" \
    "BS: re-running in bash did not help (loop), stopped" >&2
  exit 1
fi

# Реестр оболочек (POSIX): поиск bash 4.2+ и имя текущей оболочки
# The shell registry (POSIX): the search for bash 4.2+ and the current shell
if [ -f "${__bs_p:-.}/bootstrap/shell.sh" ]; then
  # shellcheck disable=SC1090,SC1091
  . "${__bs_p:-.}/bootstrap/shell.sh"
else
  printf '%s\n' "BS: не найден ${__bs_p:-.}/bootstrap/shell.sh — повреждённая копия BS?" \
    "BS: ${__bs_p:-.}/bootstrap/shell.sh is missing — a damaged BS copy?" >&2
  exit 1
fi

# POSIX-команда точки входа, которой bash не нужен: не ищем хозяина и не платим
# за перезапуск, даже если bash на машине есть. Явный BS_HOST_BASH не трогаем:
# он по-прежнему главнее и, если не подходит, остаётся ошибкой (тест).
# A POSIX command of an entry point needs no bash: do not search for a host and
# do not pay for a re-run even when bash is installed. An explicit BS_HOST_BASH
# is left alone: it still wins and, if it does not fit, stays an error (test).
if [ -n "${BS_POSIX_CMDS:-}" ] && [ -z "${BS_HOST_BASH:-}" ] \
    && bs_shell_posix_command "$@"; then
  __bs_t_fam=$(bs_shell_family)
  __bs_t_skip=1
  # bash 4.2+ в режиме POSIX (bash как sh) — тоже POSIX-оболочка: команду можно
  # выполнить здесь, принудительно выбрав POSIX-часть ядра. Старый bash (<4.2)
  # по-прежнему перезапускаем: полное ядро ему недоступно.
  # bash 4.2+ in POSIX mode (bash as sh) is a POSIX shell too: the command can run
  # here with the POSIX part of the kernel forced. An old bash (<4.2) is still
  # re-run: it cannot host the full kernel.
  if [ "$__bs_t_fam" = bash ]; then
    __bs_t_maj=$(bs_shell_version_major)
    __bs_t_min=$(bs_shell_version_minor)
    if [ "$__bs_t_maj" -lt 4 ] \
        || { [ "$__bs_t_maj" -eq 4 ] && [ "$__bs_t_min" -lt 2 ]; }; then
      __bs_t_skip=0
    fi
  fi
  if [ "$__bs_t_skip" = 1 ]; then
    # shellcheck disable=SC2034  # читают bs и init.sh в этом же процессе; не export, чтобы не течь в детей / read by bs and init.sh in this process; not exported, so it does not leak into children
    BS_POSIX_MODE=1
    BS_ORIGIN_SHELL=$__bs_t_fam
    [ "$BS_ORIGIN_SHELL" = bash ] && BS_ORIGIN_SHELL="sh"
    export BS_ORIGIN_SHELL
    unset __bs_t_self __bs_t_first __bs_t_host __bs_t_fam __bs_t_skip \
      __bs_t_maj __bs_t_min
    return 0
  fi
  unset __bs_t_fam __bs_t_skip __bs_t_maj __bs_t_min
fi

__bs_t_host=$(bs_shell_host_find 2>/dev/null) || __bs_t_host=''

if [ -n "$__bs_t_host" ]; then
  # Режим POSIX у нового bash не нужен: он запускается под своим именем
  # The new bash must not be in POSIX mode: it starts under its own name
  unset POSIXLY_CORRECT
  # Откуда запустили: bash, дошедший до трамплина (старый или в режиме POSIX),
  # ведёт себя как sh. Нужно для --strict-shell.
  # Where it was started from: a bash that reached the trampoline (old or in
  # POSIX mode) behaves as sh. Needed by --strict-shell.
  BS_ORIGIN_SHELL=$(bs_shell_family)
  [ "$BS_ORIGIN_SHELL" = bash ] && BS_ORIGIN_SHELL="sh"
  __BS_TRAMPOLINE=1
  export __BS_TRAMPOLINE BS_ORIGIN_SHELL
  exec "$__bs_t_host" "$__bs_t_self" "$@"
fi

# Точка входа, которая умеет работать без bash (BS_POSIX_ENTRY, её ставит сама точка входа): bash 4.2+
# не найден — продолжаем в текущей оболочке с POSIX-частью ядра. Явный BS_HOST_BASH, не подошедший
# по версии, остаётся ошибкой: молчаливой замены нет.
# An entry point that can run without bash (BS_POSIX_ENTRY, set by the entry point itself): no
# bash 4.2+ found — carry on in the current shell with the POSIX part of the kernel. An explicit
# BS_HOST_BASH that does not fit stays an error: there is no silent fallback.
if [ -n "${BS_POSIX_ENTRY:-}" ] && [ -z "${BS_HOST_BASH:-}" ]; then
  unset __bs_t_self __bs_t_first __bs_t_host
  return 0
fi

# Подходящего bash нет — объясняем, а не падаем на «Bad substitution»
# No capable bash — explain instead of failing with "Bad substitution"
__bs_t_fam=$(bs_shell_family)
{
  printf '%s\n' "BS: нужен bash 4.2+, а запущено: ${__bs_t_fam}; подходящий bash на машине не найден."
  printf '%s\n' "BS: bash 4.2+ is required, running: ${__bs_t_fam}; no suitable bash was found on this machine."
  if [ -n "${BS_HOST_BASH:-}" ]; then
    printf '%s\n' "BS_HOST_BASH=${BS_HOST_BASH} не является bash 4.2+ / is not a bash 4.2+"
  fi
  printf '%s\n' "" \
    "Установите bash / Install bash:" \
    "  Alpine:  apk add bash" \
    "  Debian:  apt install bash" \
    "  Fedora:  dnf install bash" \
    "  macOS:   brew install bash" \
    "Либо укажите свой / Or point to yours:  BS_HOST_BASH=/path/to/bash $__bs_t_self"
} >&2
exit 1
