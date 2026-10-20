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
        eq "$(probe "${sh_bin}" 'args::define a b; args::flag v; args::describe a "x"; args::level 1 c; bs_args_parse c --v; echo "rc=$? $(args::get 1) $(args::flag_get v)"')" "rc=0 c 1" "${sh_name}: args::* are aliases of bs_args_*"
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
