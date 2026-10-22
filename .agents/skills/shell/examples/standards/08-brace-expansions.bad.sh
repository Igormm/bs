#!/usr/bin/env bash
#
# BAD: without braces, $base_2026 is a different (unset) variable, not $base
# followed by the literal "_2026".
# expect-shellcheck: SC2250
base="report"
name="$base_2026.txt"
printf '%s\n' "$name"
