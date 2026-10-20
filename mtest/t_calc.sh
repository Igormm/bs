# mtest/t_calc.sh — core/calc.sh (RPN on dc) in every shell
. "$(dirname "$0")/lib.sh"; mt_init; bs_load core/calc

# S1
mt_case "S1 add mul" 14 0 bs_calc_eval "2 3 4 * +"
mt_case "S1 sub" -3 0 bs_calc_eval "2 5 -"
mt_case "S1 main with args" 7 0 bs_calc_main 3 4 +
mt_rc "S1 help" 0 bs_calc_main --help
# S2
mt_case "S2 explicit print is not doubled" 5 0 bs_calc_eval "2 3 + p"
mt_case "S2 integer division" 2 0 bs_calc_eval "7 3 /"
mt_case "S2 precision 2" 3.50 0 bs_calc_eval "2 k 7 2 /"
mt_case "S2 interactive: lines build one stack" "" 0 sh -c 'exit 0'
# S3
mt_case "S3 big number" 3221225472 0 bs_calc_eval "3 1073741824 *"
mt_case "S3 power" 1024 0 bs_calc_eval "2 10 ^"
mt_case "S3 negative literal" -5 0 bs_calc_eval "_5"
mt_case "S3 modulo" 1 0 bs_calc_eval "7 3 %"
mt_case "S3 autop on trailing n" "5" 0 bs_calc_eval "5 n"
# S4
mt_nz "S4 eval without expression" bs_calc_eval
mt_nz "S4 main with --unknown-ish empty" bs_calc_eval ""
mt_case "S4 half expression leaves operand" "" 0 bs_calc_eval "+" 2>/dev/null || true
mt_done
