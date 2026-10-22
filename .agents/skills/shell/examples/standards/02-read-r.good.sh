#!/usr/bin/env bash
#
# GOOD: `read -r` treats backslashes literally, so paths and escaped data
# survive intact.
set -euo pipefail

main() {
  local line
  printf 'C:\\Users\\me\n' | while IFS= read -r line; do
    printf 'read: %s\n' "$line"
  done
}

main "$@"
