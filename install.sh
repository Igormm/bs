#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: ставит BS из dash, ash, ksh, mksh, zsh и bash; ядро в них — его POSIX-часть (BS_KERNEL_MODE=posix) / valid POSIX sh: installs BS from dash, ash, ksh, mksh, zsh and bash; the kernel in them is its POSIX part (BS_KERNEL_MODE=posix)
# @tier core — builtins, cp, mv, rm, mkdir, mktemp, chmod, grep, sed, readlink; works everywhere
#
# BS installer (Linux) / Установщик BS (Linux)
#
# Modes / Режимы:
#   1) System install / Системная установка (по умолчанию $BS_SYSTEM_PREFIX=/usr/local):
#        sudo ./install.sh
#        sudo ./install.sh install
#      Нужна возможность записи в каталоги, а не root как таковой:
#      PREFIX=/opt/x, доступный вам, ставится без sudo.
#      What counts is write access to the directories, not root itself:
#      a PREFIX=/opt/x you can write to installs without sudo.
#   2) Local install in ~/.local (no sudo) / Локальная установка в ~/.local (без sudo):
#        ./install.sh --local
#        ./install.sh --local install
#      НЕ используйте sudo с --local / do NOT use sudo with --local.
#
# Uninstall / Удаление
#   sudo ./install.sh uninstall
#   ./install.sh --local uninstall
#
# PATH helpers (local only) / Настройка PATH (только для --local):
#   ./install.sh --local --path         # print snippet / вывести сниппет
#   ./install.sh --local --update-path  # auto add to ~/.bashrc and/or ~/.zshrc / авто-добавление
#
# Important / Важно:
#   The installer COPIES files to the target location. After installation
#   the source repository can be removed. Target paths depend on mode:
#     system (default): $BS_SYSTEM_PREFIX/lib/bs + .../bin/bs  (/usr/local)
#     local  (--local): ~/.local/lib/bs    + ~/.local/bin/bs
#     custom:           $LIB_DIR/bs        + $BIN_DIR/bs
#   Install is transactional (copy aside, then rename) and never overwrites
#   or deletes what is not a BS install / BS wrapper.
#   Установка транзакционная и не трогает то, что не является установкой BS.
#
# Overrides (optional) / Переопределения (опционально):
#   PREFIX=... BIN_DIR=... LIB_DIR=...   (absolute paths / абсолютные пути)
#   BS_SYSTEM_PREFIX=...                 (system prefix, default /usr/local)
#

# Установщик умеет работать и без bash (POSIX-часть ядра): трамплин перезапускает его в bash 4.2+,
# если такой есть, иначе оставляет в текущей оболочке (dash, ash, ksh, mksh, zsh).
# The installer can run without bash too (the POSIX part of the kernel): the trampoline re-runs it
# in bash 4.2+ when there is one and otherwise leaves it in the current shell (dash, ash, ksh, mksh, zsh).
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

# Определить каталог запуска скрипта
SCRIPT_DIR="${BS_ENTRY_DIR}"

# Определить каталог с файлами установки
INSTALLER_DIR="${SCRIPT_DIR}/install"

# Проверяем, что файлы и каталоги, от которых зависит инсталлятор, на месте.
# Печатаем СРАЗУ ВСЁ, чего не хватает, а не первый попавшийся файл.
# Verify the files and directories the installer depends on are present.
# Report EVERYTHING that is missing at once, not just the first file.
installer_missing=""
for installer_item in core bootstrap lib install; do
  if [ ! -d "${SCRIPT_DIR}/${installer_item}" ]; then installer_missing="${installer_missing} ${installer_item}/"; fi
done
for installer_item in bs core/utils.sh core/const.sh core/errorhandler.sh core/logger.sh \
  core/version.sh bootstrap/init.sh bootstrap/loader.sh bootstrap/base.sh install/main.sh install/actions.sh \
  install/checks.sh install/path_manager.sh install/notice.sh; do
  if [ ! -f "${SCRIPT_DIR}/${installer_item}" ]; then installer_missing="${installer_missing} ${installer_item}"; fi
done
if [ -n "${installer_missing}" ]; then
  printf 'ERROR: Источник установщика неполон: %s\n' "${SCRIPT_DIR}" >&2
  printf '       The installer source is incomplete: %s\n' "${SCRIPT_DIR}" >&2
  printf '  Не хватает / Missing:\n' >&2
  for installer_item in ${installer_missing}; do
    printf '    - %s\n' "${installer_item}" >&2
  done
  printf '  Запускайте install.sh из полного клона или архива BS (git clone ... && cd bs).\n' >&2
  printf '  Run install.sh from a complete BS clone or archive (git clone ... && cd bs).\n' >&2
  exit 1
fi
unset installer_missing installer_item

# modules sourcing
# Подключаем ядро через bootstrap: в bash — целиком, в остальных оболочках — его POSIX-часть
# (BS_KERNEL_MODE=posix); utils.sh больше нельзя подключать в одиночку.
# Bootstrap loads the kernel: the whole of it in bash, its POSIX part in other shells
# (BS_KERNEL_MODE=posix); utils.sh can no longer be sourced alone.

# Ранние проверки local-режима — ДО bootstrap: загрузка core/config.sh создаёт
# $HOME/.config/bs, т.е. под «sudo --local» (HOME пользователя) bootstrap сам
# оставил бы в его домашнем каталоге каталог root-владельца, ещё до отказа.
# Early local-mode checks — BEFORE the bootstrap: loading core/config.sh
# creates $HOME/.config/bs, so under "sudo --local" (the user's HOME) the
# bootstrap itself would leave a root-owned directory in the user's home
# before we get to refuse.
# shellcheck disable=SC1090,SC1091
. "${INSTALLER_DIR}/notice.sh"
INSTALL_EARLY_CHECKED=0
installer_local=0 installer_action=install installer_help=0
for installer_arg in "$@"; do
  case "${installer_arg}" in
    --local) installer_local=1 ;;
    uninstall|remove) installer_action=uninstall ;;
    -h|--help) installer_help=1 ;;
    *) ;;
  esac
done
if [ "${installer_local}" = "1" ] && [ "${installer_help}" = "0" ]; then
  bs_install_require_home || exit 1
  bs_install_check_sudo_local "${installer_action}" || exit 1
  # shellcheck disable=SC2034  # read by install/main.sh
  INSTALL_EARLY_CHECKED=1
fi
unset installer_local installer_action installer_help installer_arg

# PATH запустившей оболочки: bootstrap ниже сам добавляет ~/.local/bin,
# а подсказке про PATH нужен исходный.
# PATH of the calling shell: the bootstrap below prepends ~/.local/bin
# itself, while the PATH hint needs the original one.
# shellcheck disable=SC2034  # read by install/path_manager.sh
INSTALL_ORIG_PATH="${PATH}"

BS_SILENT=1
# shellcheck disable=SC1090,SC1091
if ! . "${SCRIPT_DIR}/bootstrap/init.sh"; then
  printf 'ERROR: failed to source bootstrap: %s\n' "${SCRIPT_DIR}/bootstrap/init.sh" >&2
  exit 1
fi

# Использовать строгий режим (как только функция доступна)
bs_utils_strict

# shellcheck disable=SC1090,SC1091
if ! . "${INSTALLER_DIR}/actions.sh"; then
  printf 'ERROR: failed to source file: %s\n' "${INSTALLER_DIR}/actions.sh" >&2
  exit 1
fi

if ! command -v bs_utils_strict >/dev/null 2>&1; then
  printf 'ERROR: required function %s not defined\n' "bs_utils_strict" >&2
  exit 1
fi

# Подключить checks.sh и проверить функцию bs_check_shell_environment
if ! bs_utils_ensure_source "${INSTALLER_DIR}/checks.sh" "bs_check_shell_environment"; then
  exit 1
fi

# Проверка интерпретатора: по реальному процессу, а не по $SHELL
# Interpreter check: based on the real process, not on $SHELL
bs_check_shell_environment

# Run the modular installer / Запустить модуль инсталляции
# shellcheck disable=SC1090,SC1091
. "${INSTALLER_DIR}/main.sh"
bs_install_main "$@"
