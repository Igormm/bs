#!/usr/bin/env bash
# @shell bash4 — bash 4.2+ file behind a POSIX prologue: sh/dash/zsh/bash 3.2 re-run it in bash (bootstrap/trampoline.sh)
# @shell bash4 — файл bash 4.2+ за POSIX-прологом: sh/dash/zsh/bash 3.2 перезапускают его в bash (bootstrap/trampoline.sh)
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
__bs_r=$(readlink -f -- "$0" 2>/dev/null) && [ -n "$__bs_r" ] && __bs_p=$__bs_r
case $__bs_p in */*) __bs_p=${__bs_p%/*} ;; *) __bs_p=. ;; esac
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

# Определить каталог запуска скрипта
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")" && pwd)"

# Определить каталог с файлами установки
INSTALLER_DIR="${SCRIPT_DIR}/install"

# Проверяем, что файлы и каталоги, от которых зависит инсталлятор, на месте.
# Печатаем СРАЗУ ВСЁ, чего не хватает, а не первый попавшийся файл.
# Verify the files and directories the installer depends on are present.
# Report EVERYTHING that is missing at once, not just the first file.
installer_missing=()
for installer_item in core bootstrap lib install; do
  [[ -d "${SCRIPT_DIR}/${installer_item}" ]] || installer_missing+=("${installer_item}/")
done
for installer_item in bs core/utils.sh core/const.sh core/errorhandler.sh core/logger.sh \
  core/version.sh bootstrap/init.sh bootstrap/loader.sh install/main.sh install/actions.sh \
  install/checks.sh install/path_manager.sh install/notice.sh; do
  [[ -f "${SCRIPT_DIR}/${installer_item}" ]] || installer_missing+=("${installer_item}")
done
if (( ${#installer_missing[@]} > 0 )); then
  printf 'ERROR: Источник установщика неполон: %s\n' "${SCRIPT_DIR}" >&2
  printf '       The installer source is incomplete: %s\n' "${SCRIPT_DIR}" >&2
  printf '  Не хватает / Missing:\n' >&2
  for installer_item in "${installer_missing[@]}"; do
    printf '    - %s\n' "${installer_item}" >&2
  done
  printf '  Запускайте install.sh из полного клона или архива BS (git clone ... && cd bs).\n' >&2
  printf '  Run install.sh from a complete BS clone or archive (git clone ... && cd bs).\n' >&2
  exit 1
fi
unset installer_missing installer_item

# modules sourcing
# Подключаем полное ядро через bootstrap (utils.sh больше нельзя
# подключать в одиночку: он использует bs::guard, is::*, log::*).
# Bootstrap loads the full core (utils.sh can no longer be sourced alone:
# it relies on bs::guard, is::*, log::*).

# Ранние проверки local-режима — ДО bootstrap: загрузка core/config.sh создаёт
# $HOME/.config/bs, т.е. под «sudo --local» (HOME пользователя) bootstrap сам
# оставил бы в его домашнем каталоге каталог root-владельца, ещё до отказа.
# Early local-mode checks — BEFORE the bootstrap: loading core/config.sh
# creates $HOME/.config/bs, so under "sudo --local" (the user's HOME) the
# bootstrap itself would leave a root-owned directory in the user's home
# before we get to refuse.
# shellcheck disable=SC1090
source -- "${INSTALLER_DIR}/notice.sh"
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
if [[ "${installer_local}" == "1" && "${installer_help}" == "0" ]]; then
  install_require_home || exit 1
  install_check_sudo_local "${installer_action}" || exit 1
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
# shellcheck disable=SC1090
if ! source -- "${SCRIPT_DIR}/bootstrap/init.sh"; then
  printf 'ERROR: failed to source bootstrap: %s\n' "${SCRIPT_DIR}/bootstrap/init.sh" >&2
  exit 1
fi

# Использовать строгий режим (как только функция доступна)
utils::strict

if ! source -- "${INSTALLER_DIR}/actions.sh"; then
  printf 'ERROR: failed to source file: %s\n' "${INSTALLER_DIR}/actions.sh" >&2
  exit 1
fi

if ! declare -F -- "utils::strict" >/dev/null 2>&1; then
  printf 'ERROR: required function %q not defined\n' "utils::strict" >&2
  exit 1
fi

# Подключить checks.sh и проверить функцию check_shell_environment
if ! utils::ensure_source "${INSTALLER_DIR}/checks.sh" "check_shell_environment"; then
  exit 1
fi

# Проверка интерпретатора: по реальному процессу, а не по $SHELL
# (utils::ensure_shell_version смотрит в $SHELL и ложно падает при SHELL=zsh)
# Interpreter check: based on the real process, not on $SHELL
check_shell_environment

# Run the modular installer / Запустить модуль инсталляции
source "${INSTALLER_DIR}/main.sh" "$@"
