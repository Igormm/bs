#!/bin/sh
#
# BAD: [[ ]] is a bash/ksh/zsh keyword, undefined in POSIX sh; so is '=='
# (SC3014 — not asserted here since it isn't reported by ShellCheck 0.9.0,
# which is what this repo's Linux CI installs via unpinned apt).
# expect-shellcheck: SC3010
answer=yes
if [[ $answer == yes ]]; then
  printf 'proceeding\n'
fi
