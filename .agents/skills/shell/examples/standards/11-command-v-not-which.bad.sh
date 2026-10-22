#!/usr/bin/env bash
#
# BAD: which is an external program with non-portable output and unreliable
# exit status. Prefer the shell builtin `command -v`.
# expect-shellcheck: SC2230
if which jq > /dev/null 2>&1; then
  printf 'jq is available\n'
else
  printf 'jq is not available\n'
fi
