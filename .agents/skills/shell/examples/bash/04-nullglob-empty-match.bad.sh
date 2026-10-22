#!/usr/bin/env bash
#
# BAD: without nullglob, an unmatched pattern remains the literal string
# "*.txt", so the loop runs once for a file that does not exist.
# expect-shellcheck: none
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

main() (
  cd "$tmp"

  for file in *.txt; do
    printf 'found: %s\n' "$file"
  done
)

main "$@"
