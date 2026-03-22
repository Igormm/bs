#!/usr/bin/env bash
#
# Main installer script that orchestrates the installation process
# Uses modular approach to keep code organized
#

# Загрузить утилиты если они еще не загружены
if [[ -z "${__UTILS_SOURCED:-}" ]]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/../core/utils.sh"
fi

# Дефолтные значения для параметров \ Parse arguments
MODE="system"        # system|local
ACTION="install"     # install|uninstall
FLAG_PATH="0"        # 0|1
FLAG_UPDATE_PATH="0" # 0|1

# Parse arguments /
while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      MODE="local"; shift ;;
    --path)
      FLAG_PATH="1"; shift ;;
    --update-path)
      FLAG_UPDATE_PATH="1"; shift ;;
    -h|--help)
      helper::usage; exit 0 ;;
    install|uninstall|remove|uninstall)
      ACTION="$1"; shift ;;
    *)
      printf "ERROR: Неизвестный аргумент: %s (см. --help)\n" "$1" >&2
      exit 1 ;;
  esac
done

# Resolve paths
# SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(dirname "${SCRIPT_DIR}")/.."

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

# PATH flags (local only)
if [[ "${MODE}" == "local" && "${FLAG_PATH}" == "1" ]]; then
  helper::print_path_hint
  exit 0
fi

if [[ "${MODE}" == "local" && "${FLAG_UPDATE_PATH}" == "1" ]]; then
  actions::auto_update_path
  exit 0
fi

# Execute action
case "${ACTION}" in
  install)
    actions::do_install ;;
  uninstall|remove)
    actions::do_uninstall ;;
  *)
    printf "ERROR: Неизвестное действие: %s\n" "${ACTION}" >&2
    exit 1 ;;
esac
