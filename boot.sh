#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: находит BS_ROOT и передаёт управление bs; работает в любой оболочке, bash не нужен / valid POSIX sh: finds BS_ROOT and hands over to bs; works in any shell, no bash needed
# @tier core — builtins and readlink; works everywhere
#
#  BS Framework – STAGE-1 BOOT-LOADER
#  Назначение / Purpose:
#    - проверить среду (оболочка-хозяин);
#    - максимально быстро найти BS_ROOT;
#    - передать управление скрипту bs (stage-2).
#  Exit-codes:
#    0 – успешный запуск bs;
#    1 – не найден bootstrap/base.sh;
#    2 – не найден BS_ROOT или отсутствует bs.
#

# Точка входа умеет работать без bash: трамплин перезапускает её в bash 4.2+, если он есть,
# иначе она остаётся в текущей оболочке — bs сам решит, что ему можно выполнить.
# The entry point can run without bash: the trampoline re-runs it in a bash 4.2+ when there is
# one and otherwise it stays in the current shell — bs itself decides what it can run there.
BS_POSIX_ENTRY=1

# --- POSIX-пролог (валиден в sh/dash/ash/zsh/bash) / POSIX prologue ---------
# Если запущены не bash 4+ (sh install.sh, zsh ./bs, bash 3.2, bash как sh),
# перезапускаемся в подходящем bash или объясняем, что поставить. В bash 4+
# это одна проверка. Текст пролога одинаков во всех точках входа (тест).
# Unless run by bash 4+ (sh install.sh, zsh ./bs, bash 3.2, bash as sh), re-run
# in a capable bash or explain what to install. In bash 4+ it is one test.
# zsh меняет $0 внутри подключаемого файла — путь точки входа запоминаем здесь
# zsh changes $0 inside a sourced file — the entry point path is saved here
__bs_s=$0
__bs_p=$0
# shell-gate: единственное место, где точка входа узнаёт свой путь (POSIX, до реестра)
# shell-gate: the one place an entry point learns its own path (POSIX, before the registry)
__bs_r=$(readlink -f -- "$0" 2>/dev/null) && [ -n "$__bs_r" ] && __bs_p=$__bs_r
case $__bs_p in */*) __bs_p=${__bs_p%/*} ;; *) __bs_p=. ;; esac
BS_ENTRY_DIR=$(cd -- "$__bs_p" >/dev/null 2>&1 && pwd -P) || BS_ENTRY_DIR=$__bs_p
# Реестр оболочек отвечает, годится ли эта оболочка в хозяева
# The shell registry answers whether this shell can be the host
# shellcheck disable=SC1091
. "$__bs_p/bootstrap/shell.sh"
if ! bs_shell_host_ok; then
  # shellcheck disable=SC1091
  . "$__bs_p/bootstrap/trampoline.sh"
fi
unset __BS_TRAMPOLINE __bs_p __bs_r __bs_s
# --- конец пролога / end of the prologue ------------------------------------
unset BS_POSIX_ENTRY

# 1. Определяем каталог, где лежит boot.sh
BOOT_DIR="${BS_ENTRY_DIR}"

# 2. Pre-kernel: POSIX-часть (bootstrap/base.sh) работает в любой оболочке.
#    Строгий режим включается именованной pre-kernel функцией bs_strict.
#    Pre-kernel: the POSIX part (bootstrap/base.sh) works in any shell.
#    Strict mode is enabled via the named pre-kernel helper bs_strict.
if [ -f "${BOOT_DIR}/bootstrap/base.sh" ]; then
  # shellcheck disable=SC1090,SC1091
  . "${BOOT_DIR}/bootstrap/base.sh"
  bs_strict
else
  printf 'ERROR: bootstrap/base.sh not found in %s\n' "$BOOT_DIR" >&2
  exit 1
fi

# 3. BS_ROOT: приоритет поиска
#  1) Уже экспортирован внешним скриптом
#  2) Рядом лежит файл «bs» и bootstrap/init.sh
#  3) Системные/пользовательские префиксы
if [ -z "${BS_ROOT:-}" ]; then
  if [ -f "${BOOT_DIR}/bs" ] && [ -f "${BOOT_DIR}/bootstrap/init.sh" ]; then
    BS_ROOT=$BOOT_DIR
  else
    for prefix in "${HOME}/.local/lib/bs" "/usr/local/lib/bs"; do
      if [ -f "${prefix}/bs" ] && [ -f "${prefix}/bootstrap/init.sh" ]; then
        BS_ROOT=$prefix
        break
      fi
    done
  fi
fi

# 4. Валидация
if [ -z "${BS_ROOT:-}" ]; then
  printf 'ERROR: BS framework not found (searched: repo, ~/.local/lib/bs, /usr/local/lib/bs)\n' >&2
  exit 2
fi

if [ ! -x "${BS_ROOT}/bs" ]; then
  printf 'ERROR: bs script not found or not executable in BS_ROOT=%s\n' "$BS_ROOT" >&2
  exit 2
fi

# 5. Передаём управление «настоящему» фреймворку
#    Все аргументы, STDIN/STDERR/STDOUT остаются без изменений.
exec "${BS_ROOT}/bs" "$@"
