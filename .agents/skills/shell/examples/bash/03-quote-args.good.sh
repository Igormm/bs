#!/usr/bin/env bash
#
# GOOD: forward arguments verbatim with "$@" — each stays one argument, even with
# spaces.
set -euo pipefail

show() {
  printf 'received %s argument(s)\n' "$#"
}

main() {
  set -- "one" "two words"
  show "$@"
}

main "$@"
