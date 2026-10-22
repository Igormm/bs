#!/bin/bash
#
# BAD: /bin/bash is bash 3.2 on macOS (no associative arrays, no ${var,,}) and
# does not exist on NixOS or some BSDs. Portability pitfall, not a ShellCheck
# code — /bin/bash is a valid absolute path.
# expect-shellcheck: none
set -euo pipefail

printf 'running under bash %s\n' "${BASH_VERSION}"
