#!/usr/bin/env bash
#
# BAD: [ ] is an ordinary command. An empty $answer collapses the arguments and
# the test fails with "unary operator expected".
# expect-shellcheck: SC2292
answer=""
[ $answer = yes ] && printf 'yes\n'
