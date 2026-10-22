#!/usr/bin/env bash
#
# GOOD: braces separate the variable name from the characters that follow it.
set -euo pipefail

main() {
  local base="report"
  local name="${base}_2026.txt"
  printf '%s\n' "${name}"
}

main "$@"
