#!/usr/bin/env bash
#
# BAD: parsing `ls` breaks on spaces, newlines, and glob characters in filenames.
# expect-shellcheck: SC2045
for f in $(ls *.txt); do
  printf '%s\n' "$f"
done
