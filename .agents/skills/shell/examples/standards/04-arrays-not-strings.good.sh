#!/usr/bin/env bash
#
# GOOD: hold a list in an array and expand it quoted with "${arr[@]}", so an
# element containing a space stays exactly one argument.
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

main() {
  local files=("first file.txt" "second.txt")
  local f
  for f in "${files[@]}"; do
    : > "$tmp/$f"
  done

  local n
  n="$(find "$tmp" -type f | wc -l | tr -d ' ')"
  printf 'created %s file(s)\n' "$n"
}

main "$@"
