# mtest/t_var.sh — core/var.sh in every shell (stateful: runs in the current shell)
. "$(dirname "$0")/lib.sh"; mt_init

# S1
mt_rc "S1 is_name" 0 bs_var_is_name abc_1
bs_var_set MT_X hello; mt_eq "S1 set+get" hello "$(bs_var_get MT_X)"
mt_rc "S1 is_set after set" 0 bs_var_is_set MT_X
bs_var_unset MT_X; mt_rc "S1 is_set after unset" 1 bs_var_is_set MT_X
bs_var_default MT_D dflt; mt_eq "S1 default sets" dflt "$(bs_var_get MT_D)"
bs_var_append MT_D "+x"; mt_eq "S1 append" "dflt+x" "$(bs_var_get MT_D)"

# S2
bs_var_default MT_D other; mt_eq "S2 default keeps existing" "dflt+x" "$(bs_var_get MT_D)"
bs_var_set MT_E ""; mt_rc "S2 empty value is set" 0 bs_var_is_set MT_E
mt_rc "S2 never set" 1 bs_var_is_set MT_NEVER_SET
bs_var_append MT_NEW "a"; mt_eq "S2 append to unset" a "$(bs_var_get MT_NEW)"
mt_rc "S2 unset of unset is ok" 0 bs_var_unset MT_NEVER_SET

# S3
mt_rc "S3 name with digit start" 1 bs_var_is_name 1a
mt_rc "S3 name with dash" 1 bs_var_is_name a-b
mt_rc "S3 name with dot" 1 bs_var_is_name a.b
mt_rc "S3 name underscore only" 0 bs_var_is_name _
bs_var_set MT_Q "it's \"q\" \$HOME \`id\`"; mt_eq "S3 hard value roundtrip" "it's \"q\" \$HOME \`id\`" "$(bs_var_get MT_Q)"
bs_var_set MT_NL "a
b"; mt_eq "S3 newline value" "a
b" "$(bs_var_get MT_NL)"
bs_var_set MT_SP "  lead trail  "; mt_eq "S3 spaces kept" "  lead trail  " "$(bs_var_get MT_SP)"

# S4
mt_rc "S4 set bad name" 2 bs_var_set bad-name 1
mt_rc "S4 get no name" 2 bs_var_get
mt_rc "S4 get unset" 1 bs_var_get MT_NEVER_SET
mt_rc "S4 is_name empty" 1 bs_var_is_name ""
# readonly: by the documented contract an assignment to a read-only variable ends a non-interactive
# shell, so the caller asks bs_var_is_readonly first (probed in a subshell, cannot end us)
MT_RO=1; readonly MT_RO
mt_rc "S4 is_readonly yes" 0 bs_var_is_readonly MT_RO
mt_rc "S4 is_readonly no" 1 bs_var_is_readonly MT_E
mt_rc "S4 is_readonly bad name" 2 bs_var_is_readonly 1x
mt_rc "S4 reserved internal name refused" 2 bs_var_set __bs_var_v 1

mt_done
