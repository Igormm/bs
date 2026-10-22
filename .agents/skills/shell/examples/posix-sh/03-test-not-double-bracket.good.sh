#!/bin/sh
#
# GOOD: [ ] is the POSIX test command, portable everywhere sh runs. Quote the
# operand and use a single '=' for string comparison.
set -eu

main() {
  answer=yes
  if [ "$answer" = yes ]; then
    printf 'proceeding\n'
  fi
}

main "$@"
