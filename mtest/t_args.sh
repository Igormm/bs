# mtest/t_args.sh — core/args.sh (bs_args_*) in every shell
. "$(dirname "$0")/lib.sh"; mt_init; bs_load core/args

# S1
bs_args_define go stop; bs_args_flag env value dev; bs_args_flag dry-run
bs_args_parse go --env prod --dry-run; mt_eq "S1 parse rc" 0 $?
mt_eq "S1 get 1" go "$(bs_args_get 1)"; mt_eq "S1 flag value" prod "$(bs_args_flag_get env)"
mt_rc "S1 flag set" 0 bs_args_flag_is_set dry-run
mt_rc "S1 has 1" 0 bs_args_has 1

# S2
bs_args_parse go; mt_eq "S2 default taken" dev "$(bs_args_flag_get env)"
mt_rc "S2 bool not set" 1 bs_args_flag_is_set dry-run
bs_args_parse bogus >/dev/null 2>&1; mt_eq "S2 unknown param rc" 2 $?
bs_args_parse go --bogus >/dev/null 2>&1; mt_eq "S2 unknown flag rc" 2 $?
bs_args_parse --help >/dev/null 2>&1; mt_eq "S2 help rc" 0 $?; mt_eq "S2 help requested" 1 "$ARGS_HELP_REQUESTED"

# S3 parameters
bs_args_reset; bs_args_level 1 a b; bs_args_flag n value "" number; bs_args_flag mode value fast enum:fast,slow
bs_args_parse a --n 5 --mode slow >/dev/null 2>&1; mt_eq "S3 number+enum ok" 0 $?
bs_args_parse a --n x >/dev/null 2>&1; mt_eq "S3 bad number" 2 $?
bs_args_parse a --mode medium >/dev/null 2>&1; mt_eq "S3 bad enum" 2 $?
bs_args_parse a --mode=slow >/dev/null 2>&1; mt_eq "S3 --flag=value" 0 $?
bs_args_parse "a b" >/dev/null 2>&1; mt_eq "S3 one word with a blank is not two names" 2 $?
bs_args_parse a -- x "y z" >/dev/null 2>&1; mt_eq "S3 rest after --" "y z" "$(bs_args_rest | tail -n 1)"
bs_args_reset; bs_args_define x; mt_nz "S3 reset then old tree refused" bs_args_parse go

# S4 half-scenarios
bs_args_reset
mt_nz "S4 define without names" bs_args_define
mt_nz "S4 level 0" bs_args_level 0 a
mt_nz "S4 level without names" bs_args_level 1
mt_nz "S4 flag bad type" bs_args_flag f weird
mt_nz "S4 required not a number" bs_args_required abc
bs_args_flag out value; bs_args_define a b; bs_args_required 2
bs_args_parse a >/dev/null 2>&1; mt_eq "S4 too few positionals" 2 $?
bs_args_parse a --out >/dev/null 2>&1; mt_eq "S4 flag without value" 2 $?
mt_done
