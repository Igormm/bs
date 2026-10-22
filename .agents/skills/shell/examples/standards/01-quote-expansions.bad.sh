#!/usr/bin/env bash
#
# BAD: an unquoted expansion is split on whitespace (and glob-expanded), so
# printf sees three words instead of one filename.
# expect-shellcheck: SC2086
files="quarterly report.txt"
printf '%s\n' $files
