#!/usr/bin/env bash
#
# BAD: `exit` inside a helper terminates the caller's shell when this file is
# sourced. ShellCheck cannot see the sourcing relationship across files, so this
# is a style-guide-only pitfall with no ShellCheck code.
# expect-shellcheck: none
require_cmd() {
  command -v "$1" > /dev/null 2>&1 || exit 1
}
require_cmd bash
