#!/usr/bin/env bash
#
# BAD: iterating $(cat file) splits on whitespace (so "first line" becomes two
# words) and glob-expands. Use a `while IFS= read -r` loop instead.
# expect-shellcheck: SC2013
for line in $(cat data.txt); do
  printf 'word: %s\n' "$line"
done
