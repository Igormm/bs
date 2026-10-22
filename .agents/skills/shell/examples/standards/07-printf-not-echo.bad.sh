#!/usr/bin/env bash
#
# BAD: echo's escape handling is not portable, and putting a variable in the
# printf format string reinterprets its % and \ as format directives.
# expect-shellcheck: SC2028 SC2059
echo "line one\nline two"
msg="50% off"
printf "$msg\n"
