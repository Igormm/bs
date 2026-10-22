#!/bin/sh
#
# GOOD: POSIX sh has no array type. Use the positional parameters as the list
# instead — "$@" expands each element as a separate, unsplit word.
set -eu

main() {
  set -- apple "ripe banana" cherry

  for fruit in "$@"; do
    printf 'fruit: %s\n' "$fruit"
  done
}

main "$@"
