# mtest/t_deps_guard.sh — core/deps.sh and core/prereq.sh (bs_guard) in every shell
. "$(dirname "$0")/lib.sh"; mt_init

# S1
mt_rc "S1 deps_has" 0 bs_deps_has ls
mt_rc "S1 deps_require present" 0 bs_deps_require ls
bs_guard MT_MOD; mt_eq "S1 first guard passes" 0 $?
mt_rc "S1 guard_loaded after guard" 0 bs_guard_loaded MT_MOD
mt_rc "S1 missing_tools runs" 0 bs_deps_missing_tools ls

# S2
mt_rc "S2 deps_has missing" 1 bs_deps_has no_such_cmd_zz
mt_both "S2 require missing is an error" "[ERROR] Required dependency not found: no_such_cmd_zz" 203 bs_deps_require no_such_cmd_zz
bs_guard MT_MOD; mt_eq "S2 second guard says already loaded" 1 $?
mt_rc "S2 guard_loaded of unknown" 1 bs_guard_loaded MT_NEVER

# S3
mt_rc "S3 deps_has absolute path" 0 bs_deps_has /bin/sh
mt_rc "S3 deps_has function name" 0 bs_deps_has bs_deps_has
bs_guard MT_A_1; mt_eq "S3 guard name with digit" 0 $?
mt_rc "S3 guard names are independent" 1 bs_guard_loaded MT_B_1
mt_rc "S3 list_missing prints missing" 0 bs_deps_list_missing ls no_such_cmd_zz

# S4
mt_nz "S4 guard without name" bs_guard
mt_nz "S4 require without name" bs_deps_require
mt_rc "S4 has empty" 1 bs_deps_has ""
mt_nz "S4 guard_loaded without name" bs_guard_loaded
mt_done
