#!/usr/bin/env bash
#
# BAD: building an array from an unquoted command substitution splits on
# whitespace, so "first line" wrongly becomes two elements (and globs expand).
# expect-shellcheck: SC2207
lines=($(printf '%s\n' 'first line' 'second line'))
printf 'element count: %s\n' "${#lines[@]}"
