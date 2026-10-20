# mtest/t_nu.nu — the core from nushell through `bs call` (nushell cannot source POSIX code)
# mtest/t_nu.nu — ядро из nushell через `bs call` (nushell не умеет подключать POSIX-код)
# Each case: [block, name, [function and args], expected stdout, expected exit code]
let root = ($env.MT_ROOT? | default (pwd))
let bs = ($root | path join "bs")

let cases = [
  # S1 main scenarios / основные
  [S1 "str upper" [bs_str_upper abc] "ABC" 0]
  [S1 "str trim" [bs_str_trim "  a b  "] "a b" 0]
  [S1 "str join" [bs_str_join "," a b c] "a,b,c" 0]
  [S1 "str repeat" [bs_str_repeat ab 3] "ababab" 0]
  [S1 "num add" [bs_num_add 2 3] "5" 0]
  [S1 "num mul" [bs_num_mul 6 7] "42" 0]
  [S1 "num cmp" [bs_num_cmp 1 2] "-1" 0]
  [S1 "version codename" [bs_version_codename] "Lingoa" 0]
  [S1 "human size" [bs_utils_human_size 1536] "1.5 KiB" 0]
  [S1 "error description" [bs_const_error_description 2] "Invalid arguments / Неверные аргументы" 0]
  [S1 "is_number" [bs_is_number 42] "" 0]
  [S1 "config default" [bs_config_get BS_FILES_ATOMIC] "false" 0]
  # S2 alternative scenarios / альтернативные
  [S2 "contains no" [bs_str_contains hello xyz] "" 1]
  [S2 "div by zero" [bs_num_div 1 0] "" 2]
  [S2 "is_number no" [bs_is_number 1a] "" 1]
  [S2 "has missing command" [bs_utils_has no_such_cmd_zz] "" 1]
  [S2 "compare less" [bs_version_compare "1.2.3" "1.10.0"] "" 2]
  [S2 "config unknown key" [bs_config_get NEVER_DEFINED_KEY] "" 2]
  [S2 "unknown function" [bs_no_such_fn] "" 127]
  # S3 parameter variants / варианты параметров
  [S3 "replace glob literal" [bs_str_replace "a*b" "*" "."] "a.b" 0]
  [S3 "width cyrillic" [bs_str_width "привет"] "6" 0]
  [S3 "mul beyond 32 bit" [bs_num_mul 3 1073741824] "3221225472" 0]
  [S3 "add leading zeros" [bs_num_add "08" 9] "17" 0]
  [S3 "human 3 GiB" [bs_utils_human_size 3221225472] "3.0 GiB" 0]
  [S3 "join empty item" [bs_str_join "," a "" c] "a,,c" 0]
  [S3 "version numeric not lexical" [bs_version_compare "1.10" "1.9"] "" 1]
  # S4 half-scenarios / полусценарии
  [S4 "repeat without count" [bs_str_repeat ab] "" 1]
  [S4 "add one arg" [bs_num_add 1] "" 1]
  [S4 "is_number no arg" [bs_is_number] "" 1]
  [S4 "has no arg" [bs_utils_has] "" 1]
  [S4 "join no args" [bs_str_join] "" 0]
  [S4 "config get no key" [bs_config_get] "" 2]
]

mut pass = 0
mut fail = 0
for c in $cases {
  let r = (do { ^$bs call ...$c.2 } | complete)
  let out = ($r.stdout | str trim --right --char "\n")
  if $out == $c.3 and $r.exit_code == $c.4 {
    $pass += 1
  } else {
    $fail += 1
    print $"FAIL [nu] ($c.0) ($c.1): bs call ($c.2 | str join ' ') -> out=[($out)] rc=($r.exit_code), expected out=[($c.3)] rc=($c.4)"
  }
}
print $"RESULT nu t_nu.nu pass=($pass) fail=($fail)"
if $fail > 0 { exit 1 }
