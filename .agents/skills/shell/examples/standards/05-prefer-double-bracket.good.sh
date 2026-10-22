#!/usr/bin/env bash
#
# GOOD: [[ ]] is a Bash keyword — its operands are not word-split or globbed, so
# an empty or multi-word value cannot break the test.
set -euo pipefail

main() {
  local answer="${1:-yes}"
  if [[ $answer == yes ]]; then
    printf 'proceeding\n'
  else
    printf 'declined\n'
  fi
}

main "$@"
