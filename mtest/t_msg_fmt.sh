# mtest/t_msg_fmt.sh — core/msg.sh and core/fmt.sh in every shell
. "$(dirname "$0")/lib.sh"; mt_init

# S1
mt_case "S1 human 1536" "1.5 KiB" 0 bs_utils_human_size 1536
mt_case "S1 human MiB" "1.0 MiB" 0 bs_utils_human_size 1048576
mt_case "S1 human GiB" "1.0 GiB" 0 bs_utils_human_size 1073741824
mt_both "S1 msg_fail prints and returns 1" "[ERROR] x" 1 bs_msg_fail x
mt_both "S1 msg_invalid returns 2" "[ERROR] x:" 2 bs_msg_invalid x
mt_rc "S1 now_s is a number" 0 sh -c '. "$1/bootstrap/init.sh" >/dev/null 2>&1; bs_num_is_uint "$(bs_utils_now_s)"' x "$MT_ROOT"

# S2
mt_case "S2 human zero" "0.0 B" 0 bs_utils_human_size 0
mt_case "S2 human below 1 KiB" "1023.0 B" 0 bs_utils_human_size 1023
mt_case "S2 human 3 GiB (32-bit overflow in mksh)" "3.0 GiB" 0 bs_utils_human_size 3221225472
mt_both "S2 msg_error returns 0" "[ERROR] x" 0 bs_msg_error x

# S3
mt_case "S3 human TiB" "1.0 TiB" 0 bs_utils_human_size 1099511627776
mt_case "S3 human not a number echoes input" "x" 0 bs_utils_human_size x
mt_both "S3 msg words joined" "[ERROR] a b" 0 bs_msg_error a b
mt_eq "S3 msg_join leaves text in __bs_msg_text" "a b" "$(bs_msg_join a b; echo "$__bs_msg_text")"
printf abcdef > "$MT_ROOT/mtest/.hb"; mt_case "S3 head_bytes of a file" abc 0 bs_utils_head_bytes "$MT_ROOT/mtest/.hb" 3; rm -f "$MT_ROOT/mtest/.hb"

# S4
mt_rc "S4 human no arg" 0 bs_utils_human_size
mt_nz "S4 head_bytes of a missing file" bs_utils_head_bytes /nonexistent/zz 3
mt_done
