#!/usr/bin/env bash
#
# Main installer script that orchestrates the installation process
# Uses modular approach to keep code organized
#

# проверка файлов actions.sh, checks.sh, path_manager.sh и функций do_install, is_already_installed, print_path_hint
utils::ensure_source "${INSTALLER_DIR}/actions.sh" "do_install"
utils::ensure_source "${INSTALLER_DIR}/checks.sh" "is_already_installed"
utils::ensure_source "${INSTALLER_DIR}/path_manager.sh" "print_path_hint"

# Help message
usage() {
  cat <<'HELP'
BS installer

Usage:
  ./install.sh [--local] [install|uninstall] [--path|--update-path]
  sudo ./install.sh [install|uninstall]

Notes:
  --path and --update-path are valid only with --local.
  --path и --update-path работают только с --local.

Examples:
  sudo ./install.sh
  sudo ./install.sh install
  sudo ./install.sh uninstall

  ./install.sh --local
  sudo ./install.sh --local install
  ./install.sh --local uninstall

  ./install.sh --local --path
  ./install.sh --local --update-path
HELP
}

# Дефолтные значения для параметров \ Parse arguments
MODE="system"        # system|local
MODE_EXPLICIT="0"    # 1 если режим задан флагом --local
ACTION="install"     # install|uninstall
ACTION_EXPLICIT="0"  # 1 если действие задано явно
FLAG_PATH="0"        # 0|1
FLAG_UPDATE_PATH="0" # 0|1

# Parse arguments /
while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      MODE="local"; MODE_EXPLICIT="1"; shift ;;
    --path)
      FLAG_PATH="1"; shift ;;
    --update-path)
      FLAG_UPDATE_PATH="1"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    install|uninstall|remove)
      ACTION="$1"; ACTION_EXPLICIT="1"; shift ;;
    *)
      printf "ERROR: Неизвестный аргумент: %s (см. --help)\n" "$1" >&2
      exit 1 ;;
  esac
done

# Удаление без --local: режим определяется по тому, что реально установлено.
# Есть только локальная копия (~/.local/lib/bs), системной нет — удаляем её,
# а не требуем root ради несуществующей системной установки.
# Uninstall without --local: the mode follows what is actually installed.
# Only a local copy (~/.local/lib/bs) and no system one — remove that
# instead of demanding root for a system install that does not exist.
if [[ "${ACTION}" != "install" && "${MODE_EXPLICIT}" == "0" \
      && -z "${PREFIX:-}" && -z "${BIN_DIR:-}" && -z "${LIB_DIR:-}" \
      && ! -d "/usr/local/lib/bs" ]]; then
  if [[ -d "${HOME}/.local/lib/bs" ]]; then
    MODE="local"
    # Режим записан в манифесте установки (<lib>/.install); у копий старого
    # установщика манифеста нет — тогда режим следует из каталога.
    # The mode is recorded in the install manifest (<lib>/.install); copies
    # made by an older installer have none — then the directory decides.
    recorded_mode="$(sed -n 's/^mode=//p' "${HOME}/.local/lib/bs/.install" 2>/dev/null | head -n 1)"
    printf "Найдена локальная установка (mode=%s) — удаляется %s\n" "${recorded_mode:-local}" "${HOME}/.local/lib/bs"
    printf "Local install found (mode=%s) — removing %s\n" "${recorded_mode:-local}" "${HOME}/.local/lib/bs"
  else
    printf "BS не установлена: нет ни %s, ни %s\n" "/usr/local/lib/bs" "${HOME}/.local/lib/bs"
    printf "BS is not installed: neither %s nor %s exists\n" "/usr/local/lib/bs" "${HOME}/.local/lib/bs"
    exit 0
  fi
fi

# Resolve paths
SOURCE_ROOT="${SCRIPT_DIR}"

# Choose PREFIX based on mode
if [[ "${MODE}" == "local" ]]; then
  : "${PREFIX:="$HOME/.local"}"   # ~/.local by default
else
  : "${PREFIX:=/usr/local}"       # /usr/local by default
fi

# Derive BIN_DIR and LIB_DIR
: "${BIN_DIR:="${PREFIX}/bin"}"
: "${LIB_DIR:="${PREFIX}/lib"}"

# Final install locations
TARGET_LIB="${LIB_DIR}/bs"  # BS libraries root
TARGET_BIN="${BIN_DIR}/bs"  # wrapper executable

# PATH flags are local-only (help: valid only with --local)
# Флаги PATH работают только в local-режиме (help: только с --local)
if [[ "${FLAG_PATH}" == "1" || "${FLAG_UPDATE_PATH}" == "1" ]]; then
  if [[ "${MODE}" != "local" ]]; then
    printf "ERROR: --path и --update-path работают только с --local (см. --help)\n" >&2
    exit 1
  fi
  if [[ "${ACTION_EXPLICIT}" == "1" ]]; then
    printf "ERROR: --path/--update-path — самостоятельные режимы и не сочетаются с действием %s (см. --help)\n" "${ACTION}" >&2
    exit 1
  fi
fi

# PATH flags (local only)
if [[ "${MODE}" == "local" && "${FLAG_PATH}" == "1" ]]; then
  print_path_hint
  exit 0
fi

if [[ "${MODE}" == "local" && "${FLAG_UPDATE_PATH}" == "1" ]]; then
  auto_update_path
  exit 0
fi

# Execute action
case "${ACTION}" in
  install)
    do_install ;;
  uninstall|remove)
    do_uninstall ;;
  *)
    printf "ERROR: Неизвестное действие: %s\n" "${ACTION}" >&2
    exit 1 ;;
esac