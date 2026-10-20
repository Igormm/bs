# mtest/t_data.sh — core/data.sh (arrays and maps of the data layer) in every shell
. "$(dirname "$0")/lib.sh"; mt_init

# S1 main
bs_arr_new MT_A x y z; mt_eq "S1 arr len" 3 "$(bs_arr_len MT_A)"; mt_eq "S1 arr get" y "$(bs_arr_get MT_A 1)"
bs_arr_push MT_A w; mt_eq "S1 push" 4 "$(bs_arr_len MT_A)"
bs_map_set MT_M k v; bs_map_set MT_M k2 v2
mt_eq "S1 map get" v "$(bs_map_get MT_M k)"; mt_eq "S1 map count" 2 "$(bs_map_count MT_M)"
mt_rc "S1 map has" 0 bs_map_has MT_M k
mt_rc "S1 arr contains" 0 bs_arr_contains MT_A z
mt_eq "S1 arr join" "x,y,z,w" "$(bs_arr_join MT_A ,)"

# S2 alternative
mt_rc "S2 map has missing" 1 bs_map_has MT_M nope
mt_rc "S2 map get missing" 1 bs_map_get MT_M nope
mt_rc "S2 arr get out of range" 1 bs_arr_get MT_A 99
mt_rc "S2 arr contains missing" 1 bs_arr_contains MT_A nope
mt_eq "S2 len of unknown array" 0 "$(bs_arr_len MT_NOSUCH)"
mt_eq "S2 count of unknown map" 0 "$(bs_map_count MT_NOSUCH)"
bs_map_remove MT_M k; mt_rc "S2 removed key gone" 1 bs_map_has MT_M k
bs_map_set MT_M k2 changed; mt_eq "S2 overwrite" changed "$(bs_map_get MT_M k2)"
bs_arr_clear MT_A; mt_eq "S2 clear" 0 "$(bs_arr_len MT_A)"

# S3 parameter variants (hard values and keys)
bs_map_set MT_H "a key" "it's \"q\" \$HOME"; mt_eq "S3 key with space, hard value" "it's \"q\" \$HOME" "$(bs_map_get MT_H "a key")"
bs_map_set MT_H empty ""; mt_rc "S3 empty value is present" 0 bs_map_has MT_H empty
bs_arr_new MT_B "a b" "" "c*"; mt_eq "S3 arr keeps blanks" 3 "$(bs_arr_len MT_B)"; mt_eq "S3 arr glob item literal" "c*" "$(bs_arr_get MT_B 2)"
bs_arr_new MT_C "line1
line2"; mt_eq "S3 arr newline item" "line1
line2" "$(bs_arr_get MT_C 0)"
bs_arr_new MT_D 1 2 3; bs_arr_pop MT_D MT_R; mt_eq "S3 pop into variable" 3 "$MT_R"; bs_arr_shift MT_D MT_R; mt_eq "S3 shift into variable" 1 "$MT_R"
mt_eq "S3 left after pop+shift" 1 "$(bs_arr_len MT_D)"
mt_eq "S3 quote" "'a b'" "$(bs_quote "a b")"
bs_map_set MT_K z 1; bs_map_set MT_K a 2; bs_map_keys_to MT_K MT_KEYS; mt_eq "S3 keys count" 2 "$(bs_arr_len MT_KEYS)"

# S4 half-scenarios
mt_rc "S4 map_set bad map name" 2 bs_map_set "bad-name" k v
mt_rc "S4 arr_get no index" 1 bs_arr_get MT_B
mt_rc "S4 map_has no key" 1 bs_map_has MT_M
mt_nz "S4 pop of empty array" bs_arr_pop MT_NOSUCH MT_R2
mt_nz "S4 map_set no args" bs_map_set

mt_done
