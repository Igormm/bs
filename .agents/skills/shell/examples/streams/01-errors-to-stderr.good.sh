#!/usr/bin/env bash
#
# GOOD: diagnostics go to stderr, data goes to stdout, so the data stream stays
# clean for pipes and $(...).
set -euo pipefail

err() { printf '%s\n' "$*" >&2; }

main() {
  err "starting up"         # stderr — human-facing noise
  printf 'result=%s\n' "42" # stdout — the data
}

main "$@"
