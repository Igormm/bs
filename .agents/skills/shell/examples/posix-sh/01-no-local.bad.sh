#!/bin/sh
#
# BAD: 'local' is a bash/ksh/zsh extension; POSIX sh (and some real /bin/sh
# implementations) does not define it.
# expect-shellcheck: SC3043
double() {
  local n
  n=$1
  echo $((n * 2))
}
result=$(double 21)
printf 'result=%s\n' "$result"
