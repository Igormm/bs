#!bin/bash
# BAD: a relative interpreter path. The kernel does not PATH-search the shebang
# interpreter, so this fails to execute from any other directory.
# expect-shellcheck: SC2239
set -euo pipefail

printf 'relative interpreter path\n'
