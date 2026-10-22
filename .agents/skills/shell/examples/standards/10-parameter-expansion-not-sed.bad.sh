#!/usr/bin/env bash
#
# BAD: a subshell and a fork of sed to do what parameter expansion does in the
# current shell.
# expect-shellcheck: SC2001
path="/usr/local/bin/report generator.sh"
name=$(echo "$path" | sed 's#.*/##')
printf '%s\n' "$name"
