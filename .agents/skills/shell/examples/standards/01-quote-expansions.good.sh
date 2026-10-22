#!/usr/bin/env bash
#
# GOOD: quote every expansion so a value containing spaces or glob characters is
# passed through as a single, literal argument.
set -euo pipefail

# Script-level temp dir so the EXIT trap can still see it after main() returns.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

main() {
  local name="quarterly report.txt"
  printf 'hello\n' > "$tmp/$name"

  # Quoted redirection target and command substitution: no word-splitting.
  local lines
  lines="$(wc -l < "$tmp/$name" | tr -d ' ')"
  printf 'wrote %s line(s) to "%s"\n' "$lines" "$name"
}

main "$@"
