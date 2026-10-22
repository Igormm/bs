#!/usr/bin/env bash
#
# GOOD: parameter expansion strips the path in the current shell — no fork, no
# external process.
set -euo pipefail

main() {
  local path="/usr/local/bin/report generator.sh"
  local name="${path##*/}"
  printf '%s\n' "$name"
}

main "$@"
