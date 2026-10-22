#!/usr/bin/env bats
#
# examples.bats — behavioural gate for the runnable examples.
#
# Every `*.good.sh` must run to completion with exit 0 and no arguments, proving
# the "correct" half of each good-vs-bad pair actually works. (`*.bad.sh` files
# are demonstrations of pitfalls; their behaviour is asserted in their own
# READMEs, not here.)

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
}

@test "every *.good.sh runs and exits 0" {
  local failures=0
  local script
  while IFS= read -r script; do
    [ -n "$script" ] || continue
    run bash "$REPO_ROOT/$script"
    if [ "$status" -ne 0 ]; then
      printf '%s\n' "FAILED (exit $status): $script"
      printf '%s\n' "$output"
      failures=$((failures + 1))
    fi
  done < <(git -C "$REPO_ROOT" ls-files -co --exclude-standard -- '*.good.sh')
  [ "$failures" -eq 0 ]
}
