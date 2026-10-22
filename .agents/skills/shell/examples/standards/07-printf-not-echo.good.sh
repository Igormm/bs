#!/usr/bin/env bash
#
# GOOD: printf is portable and keeps data out of the format string.
set -euo pipefail

main() {
  local name="world"
  printf 'Hello, %s!\n' "$name"
  printf 'tab:\tdone\n'
}

main "$@"
