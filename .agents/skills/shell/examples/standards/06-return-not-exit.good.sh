#!/usr/bin/env bash
#
# GOOD: a reusable helper reports failure with `return`, letting the caller
# decide what to do. `exit` here would kill any script that sources this file.
set -euo pipefail

require_cmd() {
  command -v "$1" > /dev/null 2>&1 || return 1
}

main() {
  if require_cmd bash; then
    printf 'bash is available\n'
  fi
}

main "$@"
