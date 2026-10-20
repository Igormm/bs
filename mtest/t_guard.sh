# mtest/t_guard.sh — core/guard.sh (loads prereq on demand) in every shell; each case is a fresh child shell
. "$(dirname "$0")/lib.sh"
SHB=${MT_SH:-$(command -v "$MT_SHELL" 2>/dev/null || command -v sh)}
[ "$MT_SHELL" = ash ] && SHB="busybox ash"
run() { env -i HOME=/tmp PATH=/usr/bin:/bin $SHB -c "$1" 2>&1; }
G="$MT_ROOT/core/guard.sh"

# S1 main: with the shell layer loaded, guard.sh pulls in prereq and defines bs_guard
mt_eq "S1 bs_guard appears" ok "$(run ". '$MT_ROOT/bootstrap/shell.sh'; BS_ROOT='$MT_ROOT'; . '$G'; command -v bs_guard >/dev/null && echo ok")"
mt_eq "S1 second source is a no-op" ok "$(run ". '$MT_ROOT/bootstrap/shell.sh'; BS_ROOT='$MT_ROOT'; . '$G'; . '$G'; echo ok")"

# S2 alternative: location by BS_CURRENT_FILE instead of BS_ROOT
mt_eq "S2 found through BS_CURRENT_FILE" ok "$(run ". '$MT_ROOT/bootstrap/shell.sh'; BS_CURRENT_FILE='$G'; . '$G'; command -v bs_guard >/dev/null && echo ok")"
mt_eq "S2 bs_guard already defined: prereq not sourced again" ok "$(run ". '$MT_ROOT/bootstrap/shell.sh'; BS_ROOT='$MT_ROOT'; . '$MT_ROOT/core/prereq.sh'; . '$G'; echo ok")"

# S3 parameters: the guard flag is read-only
mt_eq "S3 flag set" 1 "$(run ". '$MT_ROOT/bootstrap/shell.sh'; BS_ROOT='$MT_ROOT'; . '$G'; echo \"\$__GUARD_SOURCED\"")"
mt_eq "S3 BS_ROOT with a space" ok "$(d=$(mktemp -d); mkdir -p "$d/a b/core"; cp "$MT_ROOT/core/prereq.sh" "$MT_ROOT/core/guard.sh" "$d/a b/core/"; run ". '$MT_ROOT/bootstrap/shell.sh'; BS_ROOT='$d/a b'; . '$d/a b/core/guard.sh'; command -v bs_guard >/dev/null && echo ok"; rm -rf "$d")"

# S4 half-scenarios: missing layer / missing location are refused with a message, not a crash
out=$(run ". '$G'; echo rc=\$?")
case "$out" in *"shell.sh is not loaded"*) mt_ok ;; *) mt_bad "S4 no shell layer" "[$out]" ;; esac
out=$(run ". '$MT_ROOT/bootstrap/shell.sh'; . '$G'; echo rc=\$?")
case "$out" in *"neither BS_ROOT nor BS_CURRENT_FILE"*) mt_ok ;; *) mt_bad "S4 no BS_ROOT" "[$out]" ;; esac
mt_done
