#!/usr/bin/env bash
#
# GOOD: command -v is a shell builtin with predictable output and exit status
# for checking whether a command is available.
set -euo pipefail

main() {
  if command -v jq > /dev/null; then
    printf 'jq is available\n'
  else
    printf 'jq is not available\n'
  fi
}

main "$@"
