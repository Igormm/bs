# mtest/t_config.sh — core/config.sh in every shell
. "$(dirname "$0")/lib.sh"; mt_init

# S1
mt_case "S1 default value" false 0 bs_config_get BS_FILES_ATOMIC
bs_config_set MT_KEY v1; mt_rc "S1 set returns 0" 0 bs_config_set MT_KEY2 v2
mt_rc "S1 list runs" 0 bs_config_list
mt_rc "S1 load is repeatable" 0 bs_config_load

# S2
mt_rc "S2 get unknown key" 2 bs_config_get MT_NEVER_DEFINED
mt_rc "S2 key usable" 0 bs_config_key_usable GOOD_KEY_1
mt_rc "S2 key not usable (dash)" 1 bs_config_key_usable bad-key

# S3 parameters: the file loader
T=$(mktemp -d)
printf '# comment\nMT_A=1\nMT_B="two words"\nMT_C='"'"'q'"'"'\n\nbad-key=3\n__bs_x=4\n' > "$T/c.conf"
bs_config_load_file "$T/c.conf"; mt_eq "S3 load_file rc" 0 $?
mt_eq "S3 plain value" 1 "$(bs_config_get MT_A)"
mt_eq "S3 double-quoted value" "two words" "$(bs_config_get MT_B)"
mt_eq "S3 single-quoted value" q "$(bs_config_get MT_C)"
mt_rc "S3 bad key skipped" 2 bs_config_get bad-key
mt_rc "S3 reserved key skipped" 2 bs_config_get __bs_x
printf 'MT_HARD=$(echo pwned)\nMT_BT=`id`\n' > "$T/h.conf"; bs_config_load_file "$T/h.conf"
mt_eq "S3 command substitution is NOT executed" '$(echo pwned)' "$(bs_config_get MT_HARD)"

# S4 half-scenarios
mt_nz "S4 get without key" bs_config_get
mt_nz "S4 set without key" bs_config_set
mt_rc "S4 load missing file" 0 bs_config_load_file "$T/none.conf"
mt_nz "S4 set with a reserved name" bs_config_set __bs_x 1
rm -rf "$T"
mt_done
