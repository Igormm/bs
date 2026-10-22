#!/usr/bin/env bash
#
# GOOD: read lines into an array with `mapfile -t` — no word-splitting, no
# globbing, and empty lines are preserved.
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

main() {
  printf '%s\n' 'first line' 'second line' > "$tmp/list.txt"

  local lines=()
  mapfile -t lines < "$tmp/list.txt"

  printf 'read %s line(s); first is "%s"\n' "${#lines[@]}" "${lines[0]}"
}

main "$@"
