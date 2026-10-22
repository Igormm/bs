#!/usr/bin/env bash
#
# GOOD: glob the files directly; the shell handles spaces and odd characters in
# names correctly, one match per word.
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

main() {
  : > "$tmp/a report.txt"
  : > "$tmp/b.txt"

  local f count=0
  for f in "$tmp"/*.txt; do
    [[ -e "$f" ]] || continue
    count=$((count + 1))
  done
  printf 'found %d .txt file(s)\n' "$count"
}

main "$@"
