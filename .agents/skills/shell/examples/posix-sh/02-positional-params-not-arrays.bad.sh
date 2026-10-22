#!/bin/sh
#
# BAD: array syntax is a bash/ksh/zsh extension; POSIX sh has no array type at
# all, indexed or associative.
# expect-shellcheck: SC3030 SC3054
fruits=(apple "ripe banana" cherry)
printf 'fruit: %s\n' "${fruits[0]}"
