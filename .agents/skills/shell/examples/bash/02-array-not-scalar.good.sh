#!/usr/bin/env bash
#
# GOOD: expand the whole array with "${arr[@]}"; index explicitly for one element.
set -euo pipefail

main() {
  local fruits=("apple" "ripe banana" "cherry")

  local f
  for f in "${fruits[@]}"; do
    printf 'fruit: %s\n' "$f"
  done
}

main "$@"
