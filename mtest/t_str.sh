# mtest/t_str.sh — core/str.sh in every shell
. "$(dirname "$0")/lib.sh"; mt_init

# S1 main scenarios / основные
mt_case "S1 upper" ABC 0 bs_str_upper abc
mt_case "S1 lower" abc 0 bs_str_lower ABC
mt_case "S1 trim" "a b" 0 bs_str_trim "  a b  "
mt_case "S1 replace" "a+b+c" 0 bs_str_replace a-b-c - +
mt_case "S1 repeat" ababab 0 bs_str_repeat ab 3
mt_case "S1 join" "a,b,c" 0 bs_str_join , a b c
mt_case "S1 before/after" "a|b" 0 sh -c '. "$1/bootstrap/init.sh" >/dev/null 2>&1; echo "$(bs_str_before a=b =)|$(bs_str_after a=b =)"' x "$MT_ROOT"
mt_rc "S1 contains yes" 0 bs_str_contains hello ell
mt_rc "S1 starts_with" 0 bs_str_starts_with hello he
mt_rc "S1 ends_with" 0 bs_str_ends_with hello lo
mt_case "S1 width" 3 0 bs_str_width abc
mt_case "S1 head" abc 0 bs_str_head abcdef 3

# S2 alternative scenarios / альтернативные
mt_rc "S2 contains no" 1 bs_str_contains hello xyz
mt_rc "S2 starts_with no" 1 bs_str_starts_with hello lo
mt_rc "S2 ends_with no" 1 bs_str_ends_with hello he
mt_case "S2 ltrim keeps right" "a " 0 bs_str_ltrim "  a "
mt_case "S2 rtrim keeps left" " a" 0 bs_str_rtrim " a  "
mt_case "S2 replace absent" abc 0 bs_str_replace abc x y
mt_case "S2 head longer than string" abc 0 bs_str_head abc 10
mt_case "S2 join one item" a 0 bs_str_join , a
mt_case "S2 before without separator" "abc" 0 bs_str_before abc =

# S3 parameter variants / варианты параметров
mt_case "S3 upper mixed+digits" "A1B2" 0 bs_str_upper a1B2
mt_case "S3 replace to empty" "abc" 0 bs_str_replace a-b-c - ""
mt_case "S3 replace multi-char" "xyzxyz" 0 bs_str_replace abab ab xyz
mt_case "S3 replace glob chars literal" "a.b" 0 bs_str_replace "a*b" "*" "."
mt_case "S3 trim only blanks" "" 0 bs_str_trim "   "
mt_case "S3 trim keeps inner" "a   b" 0 bs_str_trim " a   b "
mt_case "S3 repeat zero" "" 0 bs_str_repeat ab 0
mt_case "S3 join with space sep" "a b" 0 bs_str_join " " a b
mt_case "S3 join empty item" "a,,c" 0 bs_str_join , a "" c
mt_case "S3 width cyrillic" 6 0 bs_str_width "привет"
mt_case "S3 width empty" 0 0 bs_str_width ""
mt_rc "S3 contains empty needle" 0 bs_str_contains hello ""
mt_rc "S3 contains glob star literal" 1 bs_str_contains hello "h*o"

# S4 half-scenarios / полусценарии
mt_rc "S4 repeat without count" 1 bs_str_repeat ab
mt_rc "S4 repeat non-number" 1 bs_str_repeat ab x
mt_rc "S4 upper no arg" 0 bs_str_upper
mt_rc "S4 replace no args" 0 bs_str_replace
mt_rc "S4 join no args" 0 bs_str_join
mt_rc "S4 contains one arg (empty needle)" 0 bs_str_contains hello
mt_rc "S4 head no count" 1 bs_str_head abcdef

mt_done
