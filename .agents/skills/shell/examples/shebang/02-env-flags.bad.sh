#!/usr/bin/env bash -euo pipefail
#
# BAD: without -S, the kernel hands `env` a single argument "bash -euo pipefail"
# and it looks for a program by that literal name:
#   env: 'bash -euo pipefail': No such file or directory
# ShellCheck catches this: shebangs take a single parameter on most systems.
# expect-shellcheck: SC2096
set -euo pipefail

printf 'this shebang cannot start via ./script\n'
