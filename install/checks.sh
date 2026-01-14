#!/usr/bin/env bash

# Environment checking functions for the installer

# Check if already installed
is_already_installed() {
  [[ -d "${TARGET_LIB}" && -f "${TARGET_BIN}" ]]
}

# Check shell environment
check_shell_environment() {
  if [[ -z "${BASH_VERSION:-}" ]]; then
    printf "ERROR: This installer requires bash.\n" >&2
    printf "Установщик требует bash. Запустите: bash ./install.sh\n" >&2
    exit 1
  fi
  
  # Determine shell name from environment variables or $0
  local shell_name="${ZSH_VERSION:+zsh}${BASH_VERSION:+bash}${KSH_VERSION:+ksh}"
  
  # If shell wasn't detected from version vars, check $0
  if [[ -z "$shell_name" ]]; then
      case "${0##*/}" in
          *bash*) shell_name="bash" ;;
          *zsh*) shell_name="zsh" ;;
          *ksh*) shell_name="ksh" ;;
          *sh)   shell_name="sh" ;;
          *)      shell_name="${0##*/}" ;;
      esac
  fi

  # Check if the shell is supported
  case "$shell_name" in
      bash|zsh|ksh|sh) return 0 ;;
      *)
          printf "ERROR: Unsupported shell: %s\n" "$shell_name" >&2
          printf "This script requires bash, zsh, ksh, or sh to run.\n" >&2
          exit 1
          ;;
  esac
}