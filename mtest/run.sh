#!/usr/bin/env bash
# mtest/run.sh — run every mtest/t_*.sh under bash, zsh, ash (busybox), dash; nushell via mtest/t_nu.nu
# mtest/run.sh — прогон каждого mtest/t_*.sh в bash, zsh, ash (busybox), dash; nushell — через mtest/t_nu.nu
# Usage: bash mtest/run.sh [-v] [FILE_GLOB]   (-v: also print the passing RESULT lines)
set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" # shell-gate: a bash tool of its own
verbose=0; [ "${1:-}" = "-v" ] && { verbose=1; shift; }
glob="${1:-t_*.sh}"
fail=0; total=0
for entry in "bash:bash" "zsh:zsh" "ash:busybox ash" "dash:dash"; do
  name="${entry%%:*}"; read -ra cmd <<< "${entry#*:}"
  if ! command -v "${cmd[0]}" >/dev/null 2>&1; then echo "SKIP $name: not installed"; continue; fi
  for f in "${root}"/mtest/${glob}; do
    out="$(cd "${root}" && env -i HOME="$(mktemp -d)" PATH=/usr/bin:/bin MT_ROOT="${root}" MT_SHELL="${name}" MT_FILE="$(basename "$f")" "${cmd[@]}" "$f" 2>&1)"; rc=$?
    total=$((total + 1))
    [ "${rc}" -ne 0 ] && fail=$((fail + 1))
    if [ "${rc}" -ne 0 ] || [ "${verbose}" = 1 ]; then printf '%s\n' "${out}"; fi
  done
done
if command -v nu >/dev/null 2>&1 && [ -f "${root}/mtest/t_nu.nu" ] && [[ "${glob}" == t_* ]]; then
  out="$(cd "${root}" && env -i HOME="$(mktemp -d)" PATH=/usr/bin:/bin MT_ROOT="${root}" nu "${root}/mtest/t_nu.nu" 2>&1)"; rc=$?
  total=$((total + 1)); [ "${rc}" -ne 0 ] && fail=$((fail + 1))
  if [ "${rc}" -ne 0 ] || [ "${verbose}" = 1 ]; then printf '%s\n' "${out}"; fi
else
  echo "SKIP nushell: not installed or no t_nu.nu"
fi
echo "mtest: ${total} runs, ${fail} with failures"
[ "${fail}" -eq 0 ]
