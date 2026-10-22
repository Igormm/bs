#!/usr/bin/env bash
#
# BAD: unquoted $@ re-splits each argument on whitespace, so "two words" arrives
# as two arguments.
# expect-shellcheck: SC2068
show() {
  printf 'received %s argument(s)\n' "$#"
}
set -- "one" "two words"
show $@
