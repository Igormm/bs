#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testargsportableunit.sh — core/args.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testargsportableunit.sh — core/args.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/args.sh is "@shell posix": bs_args_* must declare, parse, print help and generate
# completion the same way in every shell. The completion checksums come from the previous
# bash implementation (a differential run).
# core/args.sh — "@shell posix": bs_args_* обязаны одинаково объявлять, разбирать, печатать
# help и генерировать автодополнение в любой оболочке. Контрольные суммы автодополнения взяты
# у прежней реализации на bash (дифференциальный прогон).

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly ARGS_SH="${BS_PROJECT_ROOT}/core/args.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — ядро подключено, затем snippet; код возврата — последним словом «rc=N» там, где он нужен
probe() {
    local -r sh_bin="$1" snippet="$2"
    local f
    : > "${T}/probe.sh"
    for f in bootstrap/shell.sh core/prereq.sh core/const.sh core/logger.sh core/quiet.sh core/data.sh core/utils.sh core/lang.sh core/errorhandler.sh core/args.sh; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "${snippet}" >> "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" BS_LOG_TIMESTAMP=false BS_LOG_COLOR=false "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

readonly DECL_T1='bs_args_define cmd file...
bs_args_level 2 a b
bs_args_describe cmd "the command"
bs_args_flag verbose
bs_args_flag_describe verbose "Chatty"
bs_args_flag env value staging enum:dev,prod
bs_args_flag n value "" number'

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${ARGS_SH}'" "args.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${ARGS_SH}'" "shellcheck -s sh is clean for core/args.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${ARGS_SH}'" "core/args.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${ARGS_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare -|mapfile|read -ra|=~'" "no shell-specific constructs in core/args.sh" || true
}

test_behaviour() {
    local sh_bin sh_name out
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "$(probe "${sh_bin}" "${DECL_T1}"$'\n''bs_args_help prog')" \
"Usage: prog [flags] [cmd] [file|a|b...]

Parameters / Параметры:
  level 1: cmd
    cmd              — the command
  level 2: file | a | b

Flags / Флаги:
    --env <dev,prod>             (default: staging)
    --n <number>                
    --verbose                    — Chatty
    --help                       — Show this help and exit" "${sh_name}: help text"
        eq "$(probe "${sh_bin}" "${DECL_T1}"$'\n''bs_args_parse cmd a --verbose b --env=prod -- x "y z"; echo "rc=$? v=$(bs_args_flag_get verbose) e=$(bs_args_flag_get env) g1=$(bs_args_get 1) g3=$(bs_args_get 3) g9=$(bs_args_get 9 dflt)"; bs_args_rest')" \
"rc=0 v=1 e=prod g1=cmd g3=b g9=dflt
x
y z" "${sh_name}: parse, getters, rest"
        eq "$(probe "${sh_bin}" "${DECL_T1}"$'\n''bs_args_parse cmd; echo "e=$(bs_args_flag_get env) n=$(bs_args_flag_get n; echo rc=$?) set=$(bs_args_flag_is_set env; echo $?) has1=$(bs_args_has 1; echo $?) has2=$(bs_args_has 2; echo $?)"')" \
"e=staging n=rc=1 set=1 has1=0 has2=1" "${sh_name}: defaults, flag_is_set, has"
        eq "$(probe "${sh_bin}" "${DECL_T1}"$'\n''bs_args_parse cmd --n 7; echo "p1=$(bs_args_param 1) p2=$(bs_args_param 2 dflt) p9=$(bs_args_param 9; echo rc=$?) n=$(bs_args_flag_get n 3) e=$(bs_args_flag_get env dev) v=$(bs_args_flag_get verbose 0) z=$(bs_args_flag_get zz; echo rc=$?)"')" \
"p1=cmd p2=dflt p9=rc=1 n=7 e=staging v=0 z=rc=1" "${sh_name}: param and flag_get with a fallback"
        eq "$(probe "${sh_bin}" "${DECL_T1}"$'\n''bs_args_parse --verbose; echo "set=$(bs_args_flag_is_set verbose; echo $?)"; bs_args_parse --n 5 cmd; echo "rc=$? n=$(bs_args_flag_get n)"; bs_args_parse --n; echo "rc=$?"' | grep -E '^(set|rc)=' | tr '\n' ' ')" \
"set=0 rc=0 n=5 rc=2 " "${sh_name}: value flags and a missing value"
        out="$(probe "${sh_bin}" "${DECL_T1}"$'\n''p() { bs_args_parse "$@" >/dev/null 2>&1; printf "%s " "$?"; }; p; p bogus; p cmd a b b a; p a; p --env bad; p --n x; p --nope; p --verbose=1; p cmd --' | tr -d '\n')"
        eq "${out}" "0 2 0 2 2 2 2 2 0 " "${sh_name}: parse status for good and bad input"
        eq "$(probe "${sh_bin}" "${DECL_T1}"$'\n''bs_args_parse x -h; echo "rc=$? h=${ARGS_HELP_REQUESTED}"' | tail -n 1)" "rc=0 h=1" "${sh_name}: -h requests help"
        eq "$(probe "${sh_bin}" "${DECL_T1}"$'\n''bs_args_parse --n -h >/dev/null 2>&1; echo "h=${ARGS_HELP_REQUESTED}"; bs_args_parse -- -h >/dev/null 2>&1; echo "h=${ARGS_HELP_REQUESTED} r=$(bs_args_rest)"' | tr '\n' ' ')" "h=0 h=0 r=-h " "${sh_name}: -h as a value or after -- is not a help request"
        eq "$(probe "${sh_bin}" 'bs_args_flag out value; bs_args_flag lvl value "" number; bs_args_flag v; bs_args_required 2; bs_args_define a b; bs_args_parse a >/dev/null 2>&1; echo "rc=$?"; bs_args_parse a b >/dev/null 2>&1; echo "rc=$?"')" "rc=2
rc=0" "${sh_name}: required positionals"
        eq "$(probe "${sh_bin}" 'is_even() { [ $(( $1 % 2 )) -eq 0 ]; }; bs_args_flag n value "" is_even; bs_args_flag m value "" nosuchfn; bs_args_parse --n 4 >/dev/null 2>&1; printf "%s " $?; bs_args_parse --n 3 >/dev/null 2>&1; printf "%s " $?; bs_args_parse --m 1 >/dev/null 2>&1; printf "%s" $?')" "0 2 2" "${sh_name}: custom validator function"
        eq "$(probe "${sh_bin}" 'bs_args_define a; bs_args_parse a; bs_args_reset; bs_args_parse x >/dev/null 2>&1; echo "rc=$? n=$(bs_args_has 1; echo $?)"')" "rc=1 n=1" "${sh_name}: reset empties the tree"
        eq "$(probe "${sh_bin}" 'bs_args_level 0 a; echo "rc=$?"; bs_args_level x a; echo "rc=$?"; bs_args_level 1; echo "rc=$?"; bs_args_define; echo "rc=$?"; bs_args_flag f weird; echo "rc=$?"' | grep '^rc=' | tr '\n' ' ')" "rc=1 rc=1 rc=1 rc=1 rc=1 " "${sh_name}: bad declarations are refused"
        eq "$(probe "${sh_bin}" 'bs_args_level 1 a b; bs_args_parse "a b" >/dev/null 2>&1; echo "rc=$?"; bs_args_parse b >/dev/null 2>&1; echo "rc=$?"; bs_args_parse "a  b" >/dev/null 2>&1; echo "rc=$?"' | tr '\n' ' ')" "rc=2 rc=0 rc=2 " "${sh_name}: one word with a blank is not two neighbouring names"
        eq "$(probe "${sh_bin}" 'bs_args_define "dash-name" under_name; bs_args_flag "dry-run"; bs_args_flag "a b" value; bs_args_parse dash-name under_name --dry-run --"a b"=1 >/dev/null 2>&1; echo "rc=$? f=$(bs_args_flag_get dry-run)"')" "rc=0 f=1" "${sh_name}: names with dashes and spaces"
        eq "$(probe "${sh_bin}" '
bs_args_flag port value 80 number
bs_args_flag verbose
bs_args_flag color bool
bs_args_flag_short port p; printf "short=%s " "$?"
bs_args_flag_short verbose v; printf "shortv=%s " "$?"
bs_args_flag_repeat port; printf "repeat=%s " "$?"
bs_args_flag_bool_value color; printf "boolv=%s " "$?"
bs_args_flag_repeat verbose >/dev/null 2>&1; printf "repeatbool=%s " "$?"
bs_args_flag_bool_value port >/dev/null 2>&1; printf "boolvalue=%s " "$?"
bs_args_flag_short verbose p >/dev/null 2>&1; printf "dup=%s " "$?"
bs_args_flag_short port q >/dev/null 2>&1; printf "reassign=%s " "$?"
bs_args_flag_short missing m >/dev/null 2>&1; printf "unknown=%s " "$?"
printf "map=%s,%s repeat=%s boolv=%s stored=%s,%s,%s\n" \
  "$(bs_map_get bs_args_flag_short port)" \
  "$(bs_map_get bs_args_short_flag p)" \
  "$(bs_map_get bs_args_flag_repeat port)" \
  "$(bs_map_get bs_args_flag_bool_value color)" \
  "$(bs_map_get bs_args_flag_short port)" \
  "$(bs_map_get bs_args_short_flag p)" \
  "$(bs_map_get bs_args_short_flag q; echo rc=$?)"
')" \
"short=0 shortv=0 repeat=0 boolv=0 repeatbool=2 boolvalue=2 dup=2 reassign=2 unknown=2 map=p,port repeat=1 boolv=1 stored=p,port,rc=1" \
"${sh_name}: flag property declarations"
        eq "$(probe "${sh_bin}" '
bs_args_flag env value
bs_args_flag_repeat env
bs_args_parse --env dev --env=prod --env ""
printf "first=%s set=%s all=" "$(bs_args_flag_get env)" "$(bs_args_flag_is_set env; echo $?)"
bs_args_flag_get_all env | tr "\n" "|"
printf "\n"
bs_args_reset
bs_args_flag env value
bs_args_flag_repeat env
bs_args_parse --env dev --env bad --env prod >/dev/null 2>&1
printf "rc=%s count=%s\n" "$?" "$(bs_arr_len bs_args_repeat_values)"
')" \
"first=dev set=0 all=dev|prod||
rc=0 count=3" \
"${sh_name}: repeat values keep order"
        eq "$(probe "${sh_bin}" '
bs_args_flag env value fallback
bs_args_flag_repeat env
bs_args_parse --env= --env=x
printf "first=<%s> set=%s all=" "$(bs_args_flag_get env)" "$(bs_args_flag_is_set env; echo $?)"
bs_args_flag_get_all env | tr "\n" "|"
printf "\n"
')" "first=<> set=0 all=|x|" "${sh_name}: empty first repeat value wins over default"
        eq "$(probe "${sh_bin}" '
bs_args_flag n value "" number
bs_args_flag_repeat n
bs_args_parse --n 1 --n bad --n 3 >/dev/null 2>&1
printf "rc=%s count=%s first=%s all=" "$?" "$(bs_arr_len bs_args_repeat_values)" "$(bs_args_flag_get n)"
bs_args_flag_get_all n | tr "\n" "|"
printf "\n"
')" "rc=2 count=1 first=1 all=1|" "${sh_name}: invalid repeat occurrence is refused before storage"
        eq "$(probe "${sh_bin}" '
bs_args_flag color bool
bs_args_flag_bool_value color
bs_args_parse --color; printf "bare=%s set=%s " "$(bs_args_flag_get color)" "$(bs_args_flag_is_set color; echo $?)"
bs_args_parse --color=false; printf "false=%s set=%s " "$(bs_args_flag_get color)" "$(bs_args_flag_is_set color; echo $?)"
bs_args_parse --color=true; printf "true=%s " "$(bs_args_flag_get color)"
bs_args_parse --color=yes >/dev/null 2>&1; printf "bad=%s\n" "$?"
')" \
"bare=1 set=0 false=0 set=0 true=1 bad=2" \
"${sh_name}: bool-value long forms"
        eq "$(probe "${sh_bin}" '
bs_args_define deploy
bs_args_flag port value "" number
bs_args_flag_short port p
bs_args_flag verbose
bs_args_flag_short verbose v
bs_args_flag force
bs_args_flag_short force f
bs_args_flag output value
bs_args_flag_short output o
bs_args_flag color bool
bs_args_flag_bool_value color
bs_args_flag_short color c
bs_args_parse deploy -v -p 8080; printf "a=%s,%s,%s " "$(bs_args_flag_get port)" "$(bs_args_flag_get verbose)" "$(bs_args_get 1)"
bs_args_parse -p=8081 -f deploy; printf "b=%s,%s " "$(bs_args_flag_get port)" "$(bs_args_flag_get force)"
bs_args_parse deploy -p8082; printf "c=%s " "$(bs_args_flag_get port)"
bs_args_parse -vfp=8083 deploy; printf "d=%s,%s,%s " "$(bs_args_flag_get verbose)" "$(bs_args_flag_get force)" "$(bs_args_flag_get port)"
bs_args_parse -vo report deploy; printf "e=%s,%s " "$(bs_args_flag_get verbose)" "$(bs_args_flag_get output)"
bs_args_parse -c=false deploy; printf "f=%s,%s " "$(bs_args_flag_get color)" "$(bs_args_flag_is_set color; echo $?)"
bs_args_parse -x deploy >/dev/null 2>&1; printf "x=%s " "$?"
bs_args_parse -p -- deploy >/dev/null 2>&1; printf "missing=%s\n" "$?"
')" \
"a=8080,1,deploy b=8081,1 c=8082 d=1,1,8083 e=1,report f=0,0 x=2 missing=2" \
"${sh_name}: short flags, attached values and clusters"
        eq "$(probe "${sh_bin}" '
bs_args_define -foo
bs_args_flag port value
bs_args_flag_short port p
bs_args_parse -foo; printf "rc=%s value=%s\n" "$?" "$(bs_args_get 1)"
')" "rc=0 value=-foo" "${sh_name}: legacy dash positional survives short aliases"
        eq "$(probe "${sh_bin}" '
bs_args_flag verbose; bs_args_flag_short verbose v
bs_args_parse - >/dev/null 2>&1; printf "unknown=%s " "$?"
bs_args_reset
bs_args_define -
bs_args_flag verbose; bs_args_flag_short verbose v
bs_args_parse -; printf "declared=%s,%s\n" "$?" "$(bs_args_get 1)"
')" "unknown=2 declared=0,-" "${sh_name}: bare dash is positional, never an empty cluster"
        eq "$(probe "${sh_bin}" '
bs_args_flag x value
bs_args_flag_repeat x
bs_args_flag x bool >/dev/null 2>&1; printf "value_to_bool=%s " "$?"
bs_args_flag y bool
bs_args_flag_bool_value y
bs_args_flag y value >/dev/null 2>&1; printf "bool_to_value=%s " "$?"
printf "kinds=%s,%s props=%s,%s\n" "$(bs_map_get bs_args_flags x)" "$(bs_map_get bs_args_flags y)" "$(bs_map_has bs_args_flag_repeat x; echo $?)" "$(bs_map_has bs_args_flag_bool_value y; echo $?)"
')" "value_to_bool=2 bool_to_value=2 kinds=value,bool props=0,0" "${sh_name}: incompatible kind changes are rejected atomically"
        eq "$(probe "${sh_bin}" '
bs_args_define deploy
bs_args_flag verbose; bs_args_flag_short verbose v
bs_args_flag output value; bs_args_flag_short output o
bs_args_parse -vh >/dev/null; printf "group=%s " "$ARGS_HELP_REQUESTED"
bs_args_parse -o -h >/dev/null; printf "value=%s " "$ARGS_HELP_REQUESTED"
bs_args_parse -vo report -h >/dev/null; printf "after=%s " "$ARGS_HELP_REQUESTED"
bs_args_parse -- -h >/dev/null 2>&1; printf "raw=%s\n" "$ARGS_HELP_REQUESTED"
')" "group=1 value=0 after=1 raw=0" "${sh_name}: short help scan boundaries"
        eq "$(probe "${sh_bin}" '
bs_args_flag h value
bs_args_flag_short h h
bs_args_parse -h hello >/dev/null; printf "declared=%s value=%s\n" "$ARGS_HELP_REQUESTED" "$(bs_args_flag_get h)"
')" "declared=0 value=hello" "${sh_name}: declared h wins over built-in help"
        eq "$(probe "${sh_bin}" '
bs_args_flag verbose; bs_args_flag_short verbose v
bs_args_flag host value; bs_args_flag_short host h
bs_args_parse -vh hello; printf "value=%s,%s,%s " "$(bs_args_flag_get host)" "$(bs_args_flag_get verbose)" "$ARGS_HELP_REQUESTED"
bs_args_reset
bs_args_flag verbose; bs_args_flag_short verbose v
bs_args_flag loud; bs_args_flag_short loud h
bs_args_parse -vh; printf "bool=%s,%s,%s " "$(bs_args_flag_get loud)" "$(bs_args_flag_get verbose)" "$ARGS_HELP_REQUESTED"
bs_args_reset
bs_args_flag verbose; bs_args_flag_short verbose v
bs_args_flag color bool; bs_args_flag_bool_value color; bs_args_flag_short color h
bs_args_parse -vh=false; printf "boolv=%s,%s,%s\n" "$(bs_args_flag_get color)" "$(bs_args_flag_get verbose)" "$ARGS_HELP_REQUESTED"
')" "value=hello,1,0 bool=1,1,0 boolv=0,1,0" "${sh_name}: clustered h aliases override built-in help"
        eq "$(probe "${sh_bin}" '
bs_args_flag host value
bs_args_flag_short host h
bs_args_parse -h hello; printf "value=%s,%s\n" "$ARGS_HELP_REQUESTED" "$(bs_args_flag_get host)"
')" "value=0,hello" "${sh_name}: short h alias wins for a value flag"
        eq "$(probe "${sh_bin}" '
bs_args_flag verbose
bs_args_flag_short verbose h
bs_args_parse -h; printf "bool=%s,%s\n" "$ARGS_HELP_REQUESTED" "$(bs_args_flag_get verbose)"
')" "bool=0,1" "${sh_name}: short h alias wins for a bool flag"
    done < <(testframework::posix_shells)
}

test_completion() {
    local sh_bin sh_name target want
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        for target in "bash:4009108138 1754" "zsh:2601400582 424" "fish:3016321941 466" "nu:2844863020 523"; do
            want="${target#*:}"
            eq "$(probe "${sh_bin}" "${DECL_T1}"$'\n'"bs_args_completion prog ${target%%:*}" | cksum | cut -d' ' -f1,2)" "${want}" "${sh_name}: ${target%%:*} completion matches the bash implementation"
        done
        eq "$(probe "${sh_bin}" 'bs_args_completion prog tcsh >/dev/null 2>&1; echo "rc=$?"; bs_args_completion prog >/dev/null 2>&1; echo "rc=$?"' | tr '\n' ' ')" "rc=1 rc=1 " "${sh_name}: completion refuses an unknown shell and an empty tree"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "$(probe "${sh_bin}" 'args::define a b; args::flag v; args::describe a "x"; args::level 1 c; bs_args_parse c --v; echo "rc=$? $(args::get 1) $(args::flag_get v) $(args::param 1) $(args::flag_get w 5)"')" "rc=0 c 1 c 5" "${sh_name}: args::* are aliases of bs_args_*"
        eq "$(probe "${sh_bin}" 'args::flag e value; args::flag_repeat e; bs_args_parse --e a --e b; args::flag_get_all e | tr "\n" "|"')" "a|b|" "${sh_name}: flag_get_all alias"
    done
    # kernel in bash: the old names work, the results are real bash arrays (lib/compat/args.sh)
    load "core/args"
    args::reset
    args::define start stop
    args::flag env value dev
    args::parse start --env prod -- a "b c" >/dev/null
    eq "${ARGS_PARAMS[*]}" "start" "kernel: ARGS_PARAMS is a bash array"
    eq "${ARGS_FLAGS[env]}" "prod" "kernel: ARGS_FLAGS is a bash associative array"
    eq "${#ARGS_REST[@]}:${ARGS_REST[1]}" "2:b c" "kernel: ARGS_REST keeps words"
    eq "$(args::get 1)" "start" "kernel: args::get works"
    args::reset
    eq "${#ARGS_PARAMS[@]}:${#ARGS_FLAGS[@]}:${#ARGS_REST[@]}" "0:0:0" "kernel: args::reset empties the bash arrays"
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Behaviour in every shell / Поведение в каждой оболочке"; test_behaviour
    testframework::section "Completion / Автодополнение"; test_completion
    testframework::section "Aliases and the bash bridge / Псевдонимы и мост для bash"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
