#!/usr/bin/env bash
#
# nushell-startup-demo.sh — prove, at runtime, the single most common Nushell
# startup bug and its fix (see reference/nushell.md, "Parse-time vs runtime").
#
#   BUG: config.nu does `source generated.nu`. `source` needs a *parse-time*
#        literal path, so if the file is missing when config.nu is PARSED,
#        Nushell aborts startup with `nu::parser::sourced_file_not_found` —
#        even if the `source` is wrapped in `if (... | path exists)`.
#
#   FIX: generate the file in env.nu, which is fully evaluated BEFORE config.nu
#        is parsed. Now the path exists by the time config.nu is parsed.
#
# The demo is hermetic: it points XDG_CONFIG_HOME at a throwaway temp directory,
# so it never reads or writes your real Nushell configuration.
set -euo pipefail

if ! command -v nu > /dev/null 2>&1; then
  printf '%s\n' "nushell-startup-demo: 'nu' not found on PATH" >&2
  exit 127
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

export XDG_CONFIG_HOME="$workdir/xdg"
cfg="$XDG_CONFIG_HOME/nushell"
mkdir -p "$cfg"

fails=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1" >&2
  fails=$((fails + 1))
}

# Run Nushell with our throwaway config and return its output + exit status via
# globals (avoids masking the exit code inside a command substitution).
nu_out=""
nu_rc=0
run_nu() {
  set +e
  nu_out=$(nu --env-config "$cfg/env.nu" --config "$cfg/config.nu" -c "$1" 2>&1)
  nu_rc=$?
  set -e
}

printf '%s\n' "== CASE 1: the bug — config.nu sources a file that does not exist yet =="
printf '%s\n' '$env.DEMO = "env-loaded"' > "$cfg/env.nu"
printf '%s\n' 'source generated.nu' > "$cfg/config.nu"
run_nu 'print "startup ok"'
if [[ "$nu_rc" -ne 0 ]] && grep -q 'sourced_file_not_found' <<< "$nu_out"; then
  pass "startup aborts with a parse-time 'file not found' error"
else
  fail "expected a parse-time source error (rc=$nu_rc)"
  printf '%s\n' "$nu_out"
fi

printf '\n'
printf '%s\n' "== CASE 2: an 'if (path exists)' guard does NOT help (source is parse-time) =="
printf '%s\n' 'if ("generated.nu" | path exists) { source generated.nu }' > "$cfg/config.nu"
run_nu 'print "startup ok"'
if [[ "$nu_rc" -ne 0 ]] && grep -q 'sourced_file_not_found' <<< "$nu_out"; then
  pass "still aborts — the runtime 'if' cannot rescue a parse-time 'source'"
else
  fail "expected the guarded source to still fail at parse time (rc=$nu_rc)"
  printf '%s\n' "$nu_out"
fi

printf '\n'
printf '%s\n' "== CASE 3: the fix — env.nu generates the file before config.nu is parsed =="
cat > "$cfg/env.nu" << 'NU'
# env.nu is evaluated in full before config.nu is parsed. Generate the file that
# config.nu will `source` with a parse-time literal path.
let target = ($nu.default-config-dir | path join generated.nu)
if not ($target | path exists) {
  "$env.GENERATED = 'yes'\n" | save --force $target
}
NU
printf '%s\n' 'source generated.nu' > "$cfg/config.nu"
run_nu 'print $"generated=($env.GENERATED?)"'
if [[ "$nu_rc" -eq 0 ]] && grep -q 'generated=yes' <<< "$nu_out"; then
  pass "startup succeeds and the generated setting is in effect"
else
  fail "expected a clean startup with generated=yes (rc=$nu_rc)"
  printf '%s\n' "$nu_out"
fi

printf '\n'
if [[ "$fails" -eq 0 ]]; then
  printf '%s\n' "nushell-startup-demo: all cases passed"
  exit 0
fi
printf '%s\n' "nushell-startup-demo: $fails case(s) failed" >&2
exit 1
