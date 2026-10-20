# mtest/t_logger.sh — core/logger.sh in every shell (no timestamps, no colour)
. "$(dirname "$0")/lib.sh"; mt_init

# S1
mt_both "S1 info" "[INFO ] hi" 0 bs_log_info hi
mt_both "S1 warn" "[WARN ] w" 0 bs_log_warn w
mt_both "S1 error" "[ERROR] e" 0 bs_log_error e
mt_both "S1 success" "[SUCCESS] s" 0 bs_log_success s
mt_both "S1 fatal returns 1" "[FATAL] f" 1 bs_log_fatal f
mt_both "S1 list" "[INFO ]   * a
[INFO ]   * b" 0 bs_log_list a b
mt_both "S1 header frame" "[INFO ] ╭───╮
[INFO ] │ T │
[INFO ] ╰───╯" 0 bs_log_header T

# S2
mt_both "S2 debug hidden by default" "" 0 bs_log_debug d
mt_both "S2 info hidden at level error" "" 0 env BS_LOG_LEVEL=error sh -c 'exit 0'
BS_LOG_LEVEL=error; mt_both "S2 info below level is silent" "" 0 bs_log_info hidden; mt_both "S2 error still shown" "[ERROR] e" 0 bs_log_error e; BS_LOG_LEVEL=info
BS_LOG_LEVEL=debug; mt_both "S2 debug shown at debug" "[DEBUG] d" 0 bs_log_debug d; BS_LOG_LEVEL=info

# S3 parameters
BS_LOG_FORMAT=json; mt_both "S3 json" '{"level":"INFO","message":"hi"}' 0 bs_log_info hi
mt_both "S3 json escapes quote" '{"level":"INFO","message":"q\"x"}' 0 bs_log_info 'q"x'
mt_both "S3 json escapes backslash" '{"level":"INFO","message":"a\\b"}' 0 bs_log_info 'a\b'
BS_LOG_FORMAT=text
mt_both "S3 words joined by space" "[INFO ] a b" 0 bs_log_info a b
mt_both "S3 percent is literal" "[INFO ] 100%s" 0 bs_log_info '100%s'
mt_both "S3 header cyrillic frame (characters, not bytes)" "[INFO ] ╭──────╮
[INFO ] │ Тест │
[INFO ] ╰──────╯" 0 bs_log_header "Тест"
mt_both "S3 backslash-n stays literal" '[INFO ] a\nb' 0 bs_log_info 'a\nb'

# S4
mt_both "S4 info without message" "[INFO ] " 0 bs_log_info
mt_both "S4 info empty string" "[INFO ] " 0 bs_log_info ""
mt_nz "S4 header without text is refused" bs_log_header
mt_rc "S4 list without items" 0 bs_log_list
mt_done
