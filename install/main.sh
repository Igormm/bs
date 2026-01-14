#!/usr/bin/env bash

# Main installer script that orchestrates the installation process
# Uses modular approach to keep code organized

set -euo pipefail

# Source utility functions
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
source "${SCRIPT_DIR}/checks.sh"
source "${SCRIPT_DIR}/actions.sh"
source "${SCRIPT_DIR}/path_manager.sh"

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

# Parse arguments
MODE="system"        # system|local
ACTION="install"     # install|uninstall
FLAG_PATH="0"        # 0|1
FLAG_UPDATE_PATH="0" # 0|1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      MODE="local"; shift ;;
    --path)
      FLAG_PATH="1"; shift ;;
    --update-path)
      FLAG_UPDATE_PATH="1"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    install|uninstall|remove)
      ACTION="$1"; shift ;;
    *)
      printf "ERROR: Неизвестный аргумент: %s (см. --help)\n" "$1" >&2
      exit 1 ;;
  esac
done

# Alias: remove -> uninstall
if [[ "${ACTION}" == "remove" ]]; then
  ACTION="uninstall"
fi

# Resolve paths
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
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
  uninstall)
    do_uninstall ;;
  *)
    printf "ERROR: Неизвестное действие: %s\n" "${ACTION}" >&2
    exit 1 ;;
esac