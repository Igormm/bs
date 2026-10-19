#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, test, printf, sed; вся логика — в функции bs_install_main / valid POSIX sh: case, test, printf, sed; all the logic is in the function bs_install_main
# @tier core — builtins, sed, head; works everywhere
# shellcheck disable=SC2034  # globals are shared between install/*.sh (sourced files)
# shellcheck disable=SC2034  # глобальные переменные общие для install/*.sh (подключаемые файлы)
#
# Main installer script that orchestrates the installation process
# Uses modular approach to keep code organized
# Главный сценарий установщика: разбирает аргументы и вызывает действие
#
# ИМЕНА / NAMES
#   Real functions: bs_install_usage, bs_install_main; in bash and zsh also usage (the old name).
#   install.sh calls `bs_install_main "$@"`: a sourced file cannot take arguments in dash.
#   Настоящие функции: bs_install_usage, bs_install_main; в bash и zsh — ещё и usage (прежнее имя).
#   install.sh зовёт `bs_install_main "$@"`: подключаемый файл не принимает аргументы в dash.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# проверка файлов actions.sh, checks.sh, path_manager.sh, notice.sh и функций bs_do_install, bs_is_already_installed, bs_print_path_hint, bs_install_box
bs_utils_ensure_source "${INSTALLER_DIR}/actions.sh" "bs_do_install"
bs_utils_ensure_source "${INSTALLER_DIR}/checks.sh" "bs_is_already_installed"
bs_utils_ensure_source "${INSTALLER_DIR}/path_manager.sh" "bs_print_path_hint"
bs_utils_ensure_source "${INSTALLER_DIR}/notice.sh" "bs_install_box"

# Help message / Справка
bs_install_usage() {
  cat <<'HELP'
BS installer / Установщик BS

Usage / Использование:
  ./install.sh [--local] [install|uninstall] [--path|--update-path] [--shell NAME | --strict-shell NAME]
  sudo ./install.sh [install|uninstall]

Modes / Режимы:
  (default)  system: $BS_SYSTEM_PREFIX (по умолчанию / default /usr/local).
             Нужна возможность записи в каталоги, а не обязательно root:
             PREFIX=/opt/x, доступный вам, ставится без sudo.
             Write access to the directories is what counts, not root:
             a PREFIX=/opt/x you can write to installs without sudo.
  --local    ~/.local, без sudo / no sudo. Не используйте sudo с --local:
             файлы станут принадлежать root / do not use sudo with --local:
             files would become root-owned.

Overrides / Переопределения: PREFIX=... BIN_DIR=... LIB_DIR=...  (абсолютные пути / absolute paths)

Shell of the user / Оболочка пользователя:
  PATH и подсказки настраиваются под ВАШУ оболочку (не под ту, что исполняет
  установщик: он всегда bash). Определяется по родительскому процессу, затем
  по логин-оболочке; задать явно: --shell NAME или BS_USER_SHELL=NAME.
  NAME: bash zsh ash dash sh ksh mksh oksh osh fish nu.
  PATH and hints are set up for YOUR shell (not the one running the installer:
  that is always bash). Detected from the parent process, then the login shell; set it
  explicitly with --shell NAME or BS_USER_SHELL=NAME.

Safety / Безопасность:
  Установщик не перезаписывает и не удаляет чужое: каталог lib, не являющийся
  установкой BS, и файл bs, который не является wrapper BS, остаются нетронутыми.
  Установка транзакционная: при сбое прежняя установка остаётся на месте.
  The installer never overwrites or deletes foreign files: a lib directory that
  is not a BS install and a bs file that is not a BS wrapper stay untouched.
  Install is transactional: on failure the previous install stays in place.

Notes / Примечания:
  Уже установлено: используйте `bs update` (или удалите и поставьте заново).
  Already installed: use `bs update` (or uninstall and install again).
  --path и --update-path работают только с --local.
  --path and --update-path are valid only with --local.

Examples / Примеры:
  sudo ./install.sh
  sudo ./install.sh uninstall

  ./install.sh --local
  ./install.sh --local uninstall

  PREFIX=$HOME/opt/bs ./install.sh        # custom prefix, no root if writable
  ./install.sh --local --path
  ./install.sh --local --update-path
  ./install.sh --local --update-path --shell fish    # PATH для fish / for fish
HELP
}

# Разбор аргументов и запуск действия / Parse the arguments and run the action
bs_install_main() {
  # Дефолтные значения для параметров \ Parse arguments
  MODE="system"        # system|local
  MODE_EXPLICIT="0"    # 1 если режим задан флагом --local
  ACTION="install"     # install|uninstall
  ACTION_EXPLICIT="0"  # 1 если действие задано явно
  FLAG_PATH="0"        # 0|1
  FLAG_UPDATE_PATH="0" # 0|1

  # Parse arguments /
  while [ $# -gt 0 ]; do
    case "$1" in
      --local)
        MODE="local"; MODE_EXPLICIT="1"; shift ;;
      --path)
        FLAG_PATH="1"; shift ;;
      --update-path)
        FLAG_UPDATE_PATH="1"; shift ;;
      --strict-shell|--strict-shell=*)
        # Оболочка, для которой ставится BS (PATH, rc, подсказки): то же, что --shell NAME,
        # но жёстче: оболочка без bash 4.2+ на машине (tier unsupported) — отказ, а не подсказка
        # The shell BS is installed for (PATH, rc, hints): the same as --shell NAME, but stricter:
        # a shell with no bash 4.2+ on the machine (tier unsupported) is refused, not just hinted
        case "$1" in
          --strict-shell=*)
            __bs_mn_name=${1#--strict-shell=}; shift 1 ;;
          *)
            __bs_mn_name=${2:-}
            if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
        esac
        if [ -z "${__bs_mn_name}" ] || [ "$(bs_shell_of_name "${__bs_mn_name}")" = "unknown" ]; then
          printf "ERROR: --strict-shell требует имя оболочки: bash zsh ash dash sh ksh mksh oksh osh fish nu\n" >&2
          printf "       --strict-shell needs a shell name: bash zsh ash dash sh ksh mksh oksh osh fish nu\n" >&2
          exit 1
        fi
        BS_USER_SHELL="$(bs_shell_of_name "${__bs_mn_name}")"; export BS_USER_SHELL
        if [ "$(bs_shell_tier "${BS_USER_SHELL}")" = "unsupported" ]; then
          printf "ERROR: установка для '%s' отклонена: на машине нет bash 4.2+ (tier unsupported)\n" "${BS_USER_SHELL}" >&2
          printf "       install for '%s' refused: there is no bash 4.2+ on this machine (tier unsupported)\n" "${BS_USER_SHELL}" >&2
          exit 1
        fi
        unset __bs_mn_name ;;
      --shell)
        if [ $# -lt 2 ] || [ -z "${2:-}" ] || [ "$(bs_shell_of_name "$2")" = "unknown" ]; then
          printf "ERROR: --shell требует имя оболочки: bash zsh ash dash sh ksh mksh oksh osh fish nu\n" >&2
          printf "       --shell needs a shell name: bash zsh ash dash sh ksh mksh oksh osh fish nu\n" >&2
          exit 1
        fi
        BS_USER_SHELL="$(bs_shell_of_name "$2")"; export BS_USER_SHELL
        shift 2 ;;
      -h|--help)
        bs_install_usage; exit 0 ;;
      install|uninstall|remove)
        ACTION="$1"; ACTION_EXPLICIT="1"; shift ;;
      *)
        printf "ERROR: Неизвестный аргумент / Unknown argument: %s (см. --help / see --help)\n" "$1" >&2
        exit 1 ;;
    esac
  done

  # Переопределения пользователя запоминаем до подстановки значений по умолчанию
  # (нужны для точных команд в подсказках).
  # Remember user overrides before defaults are filled in (exact commands in hints).
  INSTALL_USER_PREFIX="${PREFIX:-}"
  INSTALL_USER_BIN_DIR="${BIN_DIR:-}"
  INSTALL_USER_LIB_DIR="${LIB_DIR:-}"
  INSTALL_AUTODETECT="0"

  # Удаление без --local: режим определяется по тому, что реально установлено.
  # Есть только локальная копия (~/.local/lib/bs), системной нет — удаляем её,
  # а не требуем root ради несуществующей системной установки.
  # Uninstall without --local: the mode follows what is actually installed.
  # Only a local copy (~/.local/lib/bs) and no system one — remove that
  # instead of demanding root for a system install that does not exist.
  if [ "${ACTION}" != "install" ] && [ "${MODE_EXPLICIT}" = "0" ] \
     && [ -z "${PREFIX:-}" ] && [ -z "${BIN_DIR:-}" ] && [ -z "${LIB_DIR:-}" ]; then
    INSTALL_AUTODETECT="1"
    if ! bs_install_std_present system && bs_install_std_present local; then
      MODE="local"
      # Режим записан в манифесте установки (<lib>/.install); у копий старого
      # установщика манифеста нет — тогда режим следует из каталога.
      # The mode is recorded in the install manifest (<lib>/.install); copies
      # made by an older installer have none — then the directory decides.
      __bs_mn_mode="$(sed -n 's/^mode=//p' "${HOME}/.local/lib/bs/.install" 2>/dev/null | head -n 1)" || __bs_mn_mode=""
      printf "Найдена локальная установка (mode=%s) — удаляется %s\n" "${__bs_mn_mode:-local}" "${HOME}/.local/lib/bs"
      printf "Local install found (mode=%s) — removing %s\n" "${__bs_mn_mode:-local}" "${HOME}/.local/lib/bs"
    fi
  fi

  # local-режиму нужен HOME: ошибка вместо «unbound variable».
  # Local mode needs HOME: an error instead of "unbound variable".
  if [ "${MODE}" = "local" ] && [ "${INSTALL_EARLY_CHECKED:-0}" != "1" ]; then
    bs_install_require_home || exit 1
  fi

  # Resolve paths
  SOURCE_ROOT="${SCRIPT_DIR}"

  # Choose PREFIX based on mode
  if [ "${MODE}" = "local" ]; then
    : "${PREFIX:="$HOME/.local"}"   # ~/.local by default
  else
    : "${PREFIX:=${BS_SYSTEM_PREFIX}}"  # /usr/local by default
  fi

  # Лишние завершающие «/» убираем (сравнение путей — по строке)
  # Strip trailing slashes (paths are compared as strings)
  if [ "${PREFIX}" != "/" ]; then PREFIX="${PREFIX%/}"; fi
  if [ -n "${BIN_DIR:-}" ] && [ "${BIN_DIR}" != "/" ]; then BIN_DIR="${BIN_DIR%/}"; fi
  if [ -n "${LIB_DIR:-}" ] && [ "${LIB_DIR}" != "/" ]; then LIB_DIR="${LIB_DIR%/}"; fi

  # Derive BIN_DIR and LIB_DIR
  : "${BIN_DIR:="${PREFIX}/bin"}"
  : "${LIB_DIR:="${PREFIX}/lib"}"

  # Final install locations
  TARGET_LIB="${LIB_DIR}/bs"  # BS libraries root
  TARGET_BIN="${BIN_DIR}/bs"  # wrapper executable

  # Bash completion location
  if [ "${MODE}" = "local" ]; then
    TARGET_COMPLETION="${HOME}/.local/share/bash-completion/completions/bs"
  elif [ "${PREFIX}" = "${BS_SYSTEM_PREFIX}" ]; then
    TARGET_COMPLETION="/usr/share/bash-completion/completions/bs"
  else
    # Свой PREFIX (Termux: $PREFIX, /opt/x): рядом с ним, а не в /usr, которого там может не быть
    # A custom PREFIX (Termux: $PREFIX, /opt/x): next to it, not in /usr, which may not exist there
    TARGET_COMPLETION="${PREFIX}/share/bash-completion/completions/bs"
  fi

  # PATH flags are local-only (help: valid only with --local)
  # Флаги PATH работают только в local-режиме (help: только с --local)
  if [ "${FLAG_PATH}" = "1" ] || [ "${FLAG_UPDATE_PATH}" = "1" ]; then
    if [ "${MODE}" != "local" ]; then
      printf "ERROR: --path и --update-path работают только с --local (см. --help)\n" >&2
      printf "       --path and --update-path are valid only with --local (see --help)\n" >&2
      exit 1
    fi
    if [ "${ACTION_EXPLICIT}" = "1" ]; then
      printf "ERROR: --path/--update-path — самостоятельные режимы и не сочетаются с действием %s (см. --help)\n" "${ACTION}" >&2
      printf "       --path/--update-path are standalone and cannot be combined with the %s action (see --help)\n" "${ACTION}" >&2
      exit 1
    fi
  fi

  # PATH flags (local only)
  if [ "${MODE}" = "local" ] && [ "${FLAG_PATH}" = "1" ]; then
    bs_print_path_hint
    exit 0
  fi

  if [ "${MODE}" = "local" ] && [ "${FLAG_UPDATE_PATH}" = "1" ]; then
    bs_auto_update_path
    exit 0
  fi

  # sudo ./install.sh --local: не ставить root-файлы в домашний каталог пользователя
  # sudo ./install.sh --local: no root-owned files inside a user's home
  if [ "${MODE}" = "local" ] && [ "${INSTALL_EARLY_CHECKED:-0}" != "1" ]; then
    case "${ACTION}" in
      install|uninstall|remove) bs_install_check_sudo_local "${ACTION}" || exit 1 ;;
    esac
  fi

  # Execute action
  case "${ACTION}" in
    install)
      bs_do_install ;;
    uninstall|remove)
      bs_do_uninstall ;;
    *)
      printf "ERROR: Неизвестное действие: %s\n" "${ACTION}" >&2
      exit 1 ;;
  esac
}

bs_shell_alias bs_install_usage usage
