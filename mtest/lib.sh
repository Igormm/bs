# mtest/lib.sh — POSIX harness of the manual (multi-shell) core tests; sourced by every t_*.sh
# mtest/lib.sh — обвязка ручных (мульти-оболочечных) тестов ядра; подключается каждым t_*.sh
#
# Every t_<module>.sh has four blocks / В каждом t_<module>.sh четыре блока:
#   S1 main scenarios / основные сценарии          S2 alternative scenarios / альтернативные сценарии
#   S3 parameter variants / варианты параметров    S4 half-scenarios (missing/partial args) / полусценарии (нет/часть аргументов)
# Output: one "FAIL" line per failed check and one "RESULT <shell> <file> pass=N fail=M" line.

MT_ROOT=${MT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
MT_SHELL=${MT_SHELL:-sh}
MT_FILE=${MT_FILE:-$(basename "$0")}
MT_PASS=0
MT_FAIL=0

mt_init() {
  BS_ENTRY_DIR=$MT_ROOT
  BS_SILENT=1
  BS_LOG_TIMESTAMP=false
  BS_LOG_COLOR=never
  export BS_LOG_TIMESTAMP BS_LOG_COLOR
  . "$MT_ROOT/bootstrap/init.sh" >/dev/null 2>&1 || { echo "FAIL init.sh does not load in $MT_SHELL"; exit 1; }
}

# mt_ok NAME — count a pass / mt_bad NAME DETAIL — count a failure
mt_ok() { MT_PASS=$((MT_PASS + 1)); }
mt_bad() { MT_FAIL=$((MT_FAIL + 1)); printf 'FAIL [%s] %s: %s\n' "$MT_SHELL" "$1" "$2"; }

# mt_eq NAME EXPECTED ACTUAL
mt_eq() {
  if [ "$2" = "$3" ]; then mt_ok; else mt_bad "$1" "expected [$2] got [$3]"; fi
}

# mt_case NAME EXPECTED_STDOUT EXPECTED_RC CMD [ARGS...] — runs in a subshell, stderr dropped
mt_case() {
  mt_name=$1; mt_exp=$2; mt_exprc=$3; shift 3
  mt_out=$("$@" 2>/dev/null); mt_rc=$?
  if [ "$mt_out" = "$mt_exp" ] && [ "$mt_rc" = "$mt_exprc" ]; then mt_ok
  else mt_bad "$mt_name" "$* -> out=[$mt_out] rc=$mt_rc, expected out=[$mt_exp] rc=$mt_exprc"; fi
}

# mt_both NAME EXPECTED_OUT EXPECTED_RC CMD... — like mt_case but stdout and stderr together
mt_both() {
  mt_name=$1; mt_exp=$2; mt_exprc=$3; shift 3
  mt_out=$("$@" 2>&1); mt_rc=$?
  if [ "$mt_out" = "$mt_exp" ] && [ "$mt_rc" = "$mt_exprc" ]; then mt_ok
  else mt_bad "$mt_name" "$* -> out=[$mt_out] rc=$mt_rc, expected out=[$mt_exp] rc=$mt_exprc"; fi
}

# mt_rc NAME EXPECTED_RC CMD... — only the status
mt_rc() {
  mt_name=$1; mt_exprc=$2; shift 2
  ( "$@" ) >/dev/null 2>&1; mt_rc=$?
  if [ "$mt_rc" = "$mt_exprc" ]; then mt_ok; else mt_bad "$mt_name" "$* -> rc=$mt_rc, expected $mt_exprc"; fi
}

# mt_nz NAME CMD... — a refusal: non-zero status, and the shell must still be alive afterwards
mt_nz() {
  mt_name=$1; shift
  ( "$@" ) >/dev/null 2>&1 && mt_rc=0 || mt_rc=$?
  if [ "$mt_rc" -ne 0 ]; then mt_ok; else mt_bad "$mt_name" "$* -> rc=0, expected a refusal"; fi
}

# mt_done — print the summary line; exit 1 on failures
mt_done() {
  printf 'RESULT %s %s pass=%s fail=%s\n' "$MT_SHELL" "$MT_FILE" "$MT_PASS" "$MT_FAIL"
  [ "$MT_FAIL" -eq 0 ]
}
