# mtest/t_const_version.sh — core/const.sh and core/version.sh in every shell
. "$(dirname "$0")/lib.sh"; mt_init
V=$(cat "$MT_ROOT/VERSION" 2>/dev/null || true)

# S1
mt_case "S1 version get = const version" "$(bs_const_version)" 0 bs_version_get
mt_rc "S1 error code 2 valid" 0 bs_const_is_valid_error_code 2
mt_case "S1 error description" "Invalid arguments / Неверные аргументы" 0 bs_const_error_description 2
mt_rc "S1 compare equal" 0 bs_version_compare 2.0 2.0
mt_rc "S1 compare greater" 1 bs_version_compare 3.0 2.9
mt_case "S1 codename not empty" "Cooloua" 0 bs_version_codename

# S2
mt_rc "S2 compare less" 2 bs_version_compare 1.2.3 1.10.0
mt_rc "S2 not a valid error code" 1 bs_const_is_valid_error_code zz
mt_case "S2 unknown code description" "Unknown error / Неизвестная ошибка" 0 bs_const_error_description 999

# S3
mt_rc "S3 compare shorter equals padded" 0 bs_version_compare 1.2 1.2.0
mt_rc "S3 numeric not lexical (10 > 9)" 1 bs_version_compare 1.10 1.9
mt_rc "S3 compare leading zeros" 0 bs_version_compare 1.02 1.2
mt_rc "S3 valid code 0" 0 bs_const_is_valid_error_code 0
mt_rc "S3 negative code invalid" 1 bs_const_is_valid_error_code -1

# S4
mt_nz "S4 compare one arg" bs_version_compare 1.2
mt_rc "S4 compare no args (empty equals empty)" 0 bs_version_compare
mt_nz "S4 valid code no arg" bs_const_is_valid_error_code
mt_nz "S4 description no arg" bs_const_error_description
mt_nz "S4 version_of without directory" bs_version_of
mt_done
