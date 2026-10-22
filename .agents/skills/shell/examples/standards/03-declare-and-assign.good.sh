#!/usr/bin/env bash
#
# GOOD: declare the local first, then assign, so a failing command substitution
# surfaces to `set -e` instead of being hidden by `local`'s own exit status.
set -euo pipefail

main() {
  local today
  today="$(date +%Y-%m-%d)" # if `date` failed, set -e catches it here
  printf 'today is %s\n' "$today"
}

main "$@"
