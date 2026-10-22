#!/usr/bin/env bash
#
# BAD: the warning is printed to stdout, so it pollutes the data stream — a
# caller doing `x=$(this-script)` captures "warning..." as part of the data.
# ShellCheck cannot detect stream misrouting; this is a review-only rule.
# expect-shellcheck: none
echo "warning: using default"
printf 'result=%s\n' "42"
