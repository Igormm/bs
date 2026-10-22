#!/usr/bin/env bash
#
# BAD: a space-separated string cannot represent an element that contains a
# space, and building an array from an unquoted expansion word-splits and globs.
# expect-shellcheck: SC2206
files="first file.txt second.txt"
arr=($files)
printf 'element count: %s\n' "${#arr[@]}"
