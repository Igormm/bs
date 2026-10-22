#!/usr/bin/env bash
#
# GOOD: read the file one line at a time; IFS= preserves leading/trailing
# whitespace and -r keeps backslashes literal.
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

main() {
  printf '%s\n' 'first line' 'second line' > "$tmp/data.txt"

  local line n=0
  while IFS= read -r line; do
    n=$((n + 1))
    printf 'line %d: %s\n' "$n" "$line"
  done < "$tmp/data.txt"
}

main "$@"
