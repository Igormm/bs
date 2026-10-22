#!/bin/sh
# install_tools.sh - Install shellcheck, shfmt, and test shells
# Supports: apk (Alpine), apt (Debian), dnf (Fedora), brew (macOS), pacman (Arch)
# Reports what was installed and where each tool is located.
#
# Usage: sh install_tools.sh [--check]
#   --check  Only report what is currently installed, do not install anything.

set -eu

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

# Verify a tool is usable and report its location
verify_tool() {
  _tool="$1"
  if command -v "$_tool" >/dev/null 2>&1; then
    _path=$(command -v "$_tool")
    _version=$("$_tool" --version 2>/dev/null | head -1 || echo "version unknown")
    printf '  %-20s %s\n' "$_tool" "found at: $_path ($_version)"
    return 0
  else
    printf '  %-20s %s\n' "$_tool" "not found"
    return 1
  fi
}

report_summary() {
  echo ""
  echo "=== Installation Summary ==="
  echo ""
  verify_tool shellcheck
  verify_tool shfmt
  verify_tool checkbashisms
  verify_tool bash
  verify_tool dash
  verify_tool zsh
  verify_tool ksh
  echo ""
}

[ "$CHECK_ONLY" -eq 1 ] && { report_summary; exit 0; }

install_apk() {
  apk add shellcheck shfmt bash dash zsh ksh mksh yash posh
}

install_apt() {
  apt-get update -q
  apt-get install -y shellcheck shfmt bash dash zsh ksh mksh
}

install_dnf() {
  dnf install -y shellcheck bash dash zsh ksh mksh
}

install_brew() {
  brew install shellcheck shfmt bash dash zsh ksh mksh
}

install_pacman() {
  pacman -S --noconfirm shellcheck shfmt bash dash zsh ksh mksh
}

if command -v apk >/dev/null 2>&1; then
  install_apk
elif command -v apt-get >/dev/null 2>&1; then
  install_apt
elif command -v dnf >/dev/null 2>&1; then
  install_dnf
elif command -v brew >/dev/null 2>&1; then
  install_brew
elif command -v pacman >/dev/null 2>&1; then
  install_pacman
else
  echo "No supported package manager found."
  echo "Install manually:"
  echo "  shellcheck: https://github.com/koalaman/shellcheck/releases"
  echo "  shfmt: https://github.com/mvdan/sh/releases"
fi

report_summary
