#!/usr/bin/env bash
#
# BAD: `read` without -r interprets backslashes, silently mangling data such as
# Windows paths or any escaped character.
# expect-shellcheck: SC2162
printf 'C:\\Users\\me\n' | while IFS= read line; do
  printf 'read: %s\n' "$line"
done
