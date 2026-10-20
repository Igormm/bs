#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testnumportableunit.sh — core/num.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testnumportableunit.sh — core/num.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/num.sh is "@shell posix": exact integer arithmetic (no 32-bit overflow in mksh), leading zeros, limits.
# core/num.sh — "@shell posix": точная целочисленная арифметика (без 32-битного переполнения в mksh), ведущие нули, пределы.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly MODULE_SH="${BS_PROJECT_ROOT}/core/num.sh"
# the files the probe sources, in dependency order / файлы, которые подключает проба, по порядку зависимостей
PROBE_FILES=(bootstrap/shell.sh core/prereq.sh core/num.sh)

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — the files are sourced (BS_CURRENT_FILE is set, as the loader does), then the snippet
# (stdout+stderr); a fresh process under env -i: the guard makes a second source in one process a no-op
probe() {
    local -r sh_bin="$1" snippet="$2"
    local f
    : > "${T}/probe.sh"
    for f in "${PROBE_FILES[@]}"; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "${snippet}" >> "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${MODULE_SH}'" "num.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${MODULE_SH}'" "shellcheck -s sh is clean for core/num.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${MODULE_SH}'" "core/num.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${MODULE_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare| \\[\\[ |printf -v'" "no shell-specific constructs in core/num.sh" || true
}

test_checks_and_dec() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=0 rc=1 rc=1 rc=1 rc=1" "$(probe "${sh_bin}" 'bs_num_is_uint 123; printf "rc=%s " "$?"; bs_num_is_uint -1; printf "rc=%s " "$?"; bs_num_is_uint ""; printf "rc=%s " "$?"; bs_num_is_uint 1a; printf "rc=%s " "$?"; bs_num_is_uint "1 2"; printf "rc=%s" "$?"')" "${sh_name}: is_uint"
        eq "rc=0 rc=0 rc=1 rc=1 rc=1" "$(probe "${sh_bin}" 'bs_num_is_int 5; printf "rc=%s " "$?"; bs_num_is_int -5; printf "rc=%s " "$?"; bs_num_is_int -; printf "rc=%s " "$?"; bs_num_is_int --5; printf "rc=%s " "$?"; bs_num_is_int +5; printf "rc=%s" "$?"')" "${sh_name}: is_int"
        eq "7 -7 0 0 0 5" "$(probe "${sh_bin}" 'for n in 007 -007 -0 0 000 5; do printf "%s " "$(bs_num_dec "$n")"; done | sed "s/ $//"')" "${sh_name}: dec strips leading zeros and -0"
        eq "999999999999999" "$(probe "${sh_bin}" 'bs_num_dec 999999999999999')" "${sh_name}: dec at the 15-digit limit"
        eq "rc=1 rc=1 rc=1" "$(probe "${sh_bin}" 'bs_num_dec 1000000000000000 >/dev/null; printf "rc=%s " "$?"; bs_num_dec x >/dev/null; printf "rc=%s " "$?"; bs_num_dec "" >/dev/null; printf "rc=%s" "$?"')" "${sh_name}: dec refuses 16 digits, text and empty"
        eq "1" "$(probe "${sh_bin}" 'bs_num_dec 00000000000000000001')" "${sh_name}: many leading zeros do not count as digits"
    done < <(testframework::posix_shells)
}

test_arithmetic() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "3221225472" "$(probe "${sh_bin}" 'bs_num_mul 3 1073741824')" "${sh_name}: 3 GiB does not overflow (mksh \$(( )) is 32-bit)"
        eq "123456789000000" "$(probe "${sh_bin}" 'bs_num_mul 123456789 1000000')" "${sh_name}: a 15-digit product"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_num_mul 999999999 999999999 >/dev/null; echo rc=$?')" "${sh_name}: a product beyond 15 digits is 1, never inexact"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_num_add 999999999999999 1 >/dev/null; echo rc=$?')" "${sh_name}: a sum beyond the limit is 1"
        eq "-2 -3 8 0" "$(probe "${sh_bin}" 'printf "%s %s %s %s" "$(bs_num_add -5 3)" "$(bs_num_sub 5 8)" "$(bs_num_add 08 0)" "$(bs_num_mul -5 0)"')" "${sh_name}: signs, leading zeros, no -0"
        eq "3 -3 3" "$(probe "${sh_bin}" 'printf "%s %s %s" "$(bs_num_div 7 2)" "$(bs_num_div -7 2)" "$(bs_num_div 7 -2 | sed s/-//)"')" "${sh_name}: div truncates toward zero"
        eq "1 -1 1" "$(probe "${sh_bin}" 'printf "%s %s %s" "$(bs_num_mod 7 2)" "$(bs_num_mod -7 2)" "$(bs_num_mod 7 -2)"')" "${sh_name}: mod has the sign of the dividend"
        eq "rc=2 rc=2" "$(probe "${sh_bin}" 'bs_num_div 5 0 >/dev/null; printf "rc=%s " "$?"; bs_num_mod 5 0 >/dev/null; printf "rc=%s" "$?"')" "${sh_name}: division by zero is 2"
        eq "rc=1 rc=1" "$(probe "${sh_bin}" 'bs_num_add a 1 >/dev/null; printf "rc=%s " "$?"; bs_num_sub 1 "" >/dev/null; printf "rc=%s" "$?"')" "${sh_name}: not an integer is 1"
        eq "-1 0 1 -1 1" "$(probe "${sh_bin}" 'printf "%s %s %s %s %s" "$(bs_num_cmp 2 10)" "$(bs_num_cmp 10 10)" "$(bs_num_cmp 10 2)" "$(bs_num_cmp -2 -1)" "$(bs_num_cmp -1 -2)"')" "${sh_name}: cmp is numeric, not textual (2 < 10)"
        eq "0" "$(probe "${sh_bin}" 'bs_num_cmp 007 7')" "${sh_name}: cmp ignores leading zeros"
        eq "1 999999999999998" "$(probe "${sh_bin}" 'printf "%s %s" "$(bs_num_div 999999999999998 999999999999998)" "$(bs_num_sub 999999999999999 1)"')" "${sh_name}: exact at the limit"
    done < <(testframework::posix_shells)
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Checks and dec / Проверки и dec"; test_checks_and_dec
    testframework::section "Arithmetic / Арифметика"; test_arithmetic
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
