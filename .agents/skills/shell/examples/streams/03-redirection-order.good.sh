#!/usr/bin/env bash
#
# GOOD: redirect stdout to the file first, then point stderr at the same place
# with 2>&1 — so both streams land in the file.
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

main() {
  {
    printf 'out\n'
    printf 'err\n' >&2
  } > "$tmp/log" 2>&1
  printf 'captured %s line(s)\n' "$(wc -l < "$tmp/log" | tr -d ' ')"
}

main "$@"
