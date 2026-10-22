#!/usr/bin/env bash
#
# BAD: `local dir="$(...)"` always exits 0 (that is `local`'s status), so a
# failure of the command substitution is silently swallowed.
# expect-shellcheck: SC2155
demo() {
  local dir="$(mktemp -d)"
  printf '%s\n' "$dir"
}
demo
