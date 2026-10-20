# mtest/t_num.sh — core/num.sh in every shell
. "$(dirname "$0")/lib.sh"; mt_init

# S1
mt_case "S1 add" 5 0 bs_num_add 2 3
mt_case "S1 sub" -3 0 bs_num_sub 2 5
mt_case "S1 mul" 42 0 bs_num_mul 6 7
mt_case "S1 div" 3 0 bs_num_div 7 2
mt_case "S1 mod" 1 0 bs_num_mod 7 3
mt_case "S1 cmp less" -1 0 bs_num_cmp 1 2
mt_case "S1 cmp equal" 0 0 bs_num_cmp 2 2
mt_case "S1 cmp greater" 1 0 bs_num_cmp 3 2
mt_rc "S1 is_uint" 0 bs_num_is_uint 12
mt_rc "S1 is_int negative" 0 bs_num_is_int -5

# S2
mt_rc "S2 is_uint negative" 1 bs_num_is_uint -1
mt_rc "S2 is_int float" 1 bs_num_is_int 1.5
mt_rc "S2 div by zero" 2 bs_num_div 1 0
mt_rc "S2 mod by zero" 2 bs_num_mod 7 0
mt_case "S2 sub to negative" -7 0 bs_num_sub -2 5
mt_case "S2 div negative truncates" -3 0 bs_num_div -7 2

# S3
mt_case "S3 dec strips zeros" 7 0 bs_num_dec 007
mt_case "S3 dec zero" 0 0 bs_num_dec 000
mt_case "S3 add leading zeros (not octal)" 17 0 bs_num_add 08 9
mt_case "S3 mul beyond 32 bit" 3221225472 0 bs_num_mul 3 1073741824
mt_case "S3 cmp big numbers" -1 0 bs_num_cmp 99999999999 100000000000
mt_case "S3 add negatives" -5 0 bs_num_add -2 -3
mt_rc "S3 is_uint plus sign" 1 bs_num_is_uint +1
mt_rc "S3 is_uint empty" 1 bs_num_is_uint ""
mt_rc "S3 is_uint spaces" 1 bs_num_is_uint "1 2"

# S4
mt_rc "S4 add non-number" 1 bs_num_add a 1
mt_rc "S4 add one arg" 1 bs_num_add 1
mt_rc "S4 add overflow" 1 bs_num_add 9223372036854775807 1
mt_rc "S4 cmp one arg" 1 bs_num_cmp 1
mt_rc "S4 mul empty" 1 bs_num_mul "" 2

mt_done
