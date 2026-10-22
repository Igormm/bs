#!/bin/sh
#
# GOOD: POSIX sh has no 'local' keyword. Command substitution already runs the
# function in a subshell, so a plain assignment inside it cannot leak out.
set -eu

double() {
  n=$1
  echo $((n * 2))
}

main() {
  result=$(double 21)
  printf 'result=%s\n' "$result"
}

main "$@"
