#!/usr/bin/env -S bash -euo pipefail
#
# GOOD: `env -S` (split-string) splits the rest of the line into words, so the
# strict-mode flags actually reach bash. This bakes `set -euo pipefail` into the
# shebang itself.

printf 'strict mode is on via the shebang\n'
