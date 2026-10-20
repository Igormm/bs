# mtest/t_errorhandler.sh — core/errorhandler.sh in every shell
. "$(dirname "$0")/lib.sh"; mt_init
T=$(mktemp -d)

# S1 main
mt_rc "S1 try ok" 0 bs_error_try true
mt_rc "S1 retry ok" 0 bs_error_retry 2 true
mt_rc "S1 ignore failure" 0 bs_error_ignore false
mt_rc "S1 timeout ok" 0 bs_error_with_timeout 5 true
mt_rc "S1 fallback used" 0 bs_error_try_with_fallback false true
mt_rc "S1 exit_code success" 0 bs_exit_code success
c1() { echo cleanup1 >> "$T/log"; }; c2() { echo cleanup2 >> "$T/log"; }
bs_cleanup_add c1; bs_cleanup_add c2; bs_cleanup_run_all
mt_eq "S1 cleanup runs LIFO" "cleanup2 cleanup1" "$(tr '\n' ' ' < "$T/log" | sed 's/ $//')"

# S2 alternative
mt_both "S2 try failure message" "[ERROR] Command failed: false" 1 bs_error_try false
mt_rc "S2 try keeps the status" 7 bs_error_try sh -c 'exit 7'
mt_both "S2 retry gives up" "[ERROR] Command failed after 3 attempts: false" 1 bs_error_retry 3 false
mt_rc "S2 timeout fires" 124 bs_error_with_timeout 1 sleep 3
mt_rc "S2 fallback when both fail" 1 bs_error_try_with_fallback false false
mt_both "S2 error_log" "[ERROR] hi" 0 bs_error_log hi

# S3 parameters
n=0; flaky() { n=$((n + 1)); [ "$n" -ge 3 ]; }
bs_error_retry 5 flaky >/dev/null 2>&1; mt_eq "S3 retry stops at first success (3 calls)" 3 "$n"
mt_rc "S3 try with args containing spaces" 0 bs_error_try test "a b" = "a b"
mt_rc "S3 exit_code by name invalid" 0 bs_exit_code invalid
mt_rc "S3 exit_code unknown name" 1 bs_exit_code zzz
mt_rc "S3 timeout 1 on fast command" 0 bs_error_with_timeout 1 true

# S4 half-scenarios
mt_rc "S4 try with no command (nothing to fail)" 0 bs_error_try
mt_rc "S4 retry without command (nothing to fail)" 0 bs_error_retry 2
mt_nz "S4 retry non-number count" bs_error_retry x true
mt_nz "S4 cleanup_add without function" bs_cleanup_add
mt_nz "S4 timeout without command" bs_error_with_timeout 1
mt_nz "S4 exit_code without name" bs_exit_code
rm -rf "$T"
mt_done
