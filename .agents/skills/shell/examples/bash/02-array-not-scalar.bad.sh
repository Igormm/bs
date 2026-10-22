#!/usr/bin/env bash
#
# BAD: a bare array reference expands to only the FIRST element, silently
# dropping the rest.
# expect-shellcheck: SC2128
fruits=("apple" "ripe banana" "cherry")
printf 'fruits = %s\n' "$fruits"
