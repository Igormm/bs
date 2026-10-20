# mtest/t_quiet.sh — core/quiet.sh (bs_utils_has/quiet/quiet_err/ignore/attempt) in every shell
. "$(dirname "$0")/lib.sh"; mt_init

# S1
mt_rc "S1 has ls" 0 bs_utils_has ls
mt_case "S1 quiet hides stdout" "" 0 bs_utils_quiet echo hi
mt_case "S1 quiet_err keeps stdout" o 0 bs_utils_quiet_err sh -c 'echo o; echo e >&2'
mt_rc "S1 ignore false" 0 bs_utils_ignore false
mt_rc "S1 attempt true" 0 bs_utils_attempt true

# S2
mt_rc "S2 has missing" 1 bs_utils_has no_such_cmd_zz
mt_rc "S2 quiet keeps status" 3 bs_utils_quiet sh -c 'exit 3'
mt_rc "S2 quiet_err keeps status" 4 bs_utils_quiet_err sh -c 'exit 4'
mt_case "S2 quiet hides stderr too" "" 0 bs_utils_quiet sh -c 'echo e >&2'
mt_rc "S2 ignore hides failure of missing command" 0 bs_utils_ignore no_such_cmd_zz

# S3
mt_rc "S3 has absolute path" 0 bs_utils_has /bin/sh
mt_rc "S3 has name with dash" 1 bs_utils_has "no-such-cmd"
mt_rc "S3 has a function" 0 bs_utils_has bs_utils_has
mt_case "S3 quiet passes args with spaces" "" 0 bs_utils_quiet test "a b" = "a b"
mt_rc "S3 quiet_err with failing test" 1 bs_utils_quiet_err test "a" = "b"

# S4
mt_rc "S4 has no arg" 1 bs_utils_has
mt_rc "S4 has empty arg" 1 bs_utils_has ""
mt_nz "S4 quiet missing command" bs_utils_quiet no_such_cmd_zz
mt_nz "S4 quiet no args or refusal" bs_utils_quiet_err no_such_cmd_zz
mt_done
