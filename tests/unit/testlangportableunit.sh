#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testquietportableunit.sh — core/lang.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testquietportableunit.sh — core/lang.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/lang.sh is "@shell posix": the bs_is_* predicates must give the same answers in every
# shell. core/lang.sh — "@shell posix": предикаты bs_is_* обязаны давать одинаковые ответы.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly SHELL_SH="${BS_PROJECT_ROOT}/bootstrap/shell.sh"
readonly PREREQ_SH="${BS_PROJECT_ROOT}/core/prereq.sh"
readonly QUIET_SH="${BS_PROJECT_ROOT}/core/quiet.sh"
readonly LANG_SH="${BS_PROJECT_ROOT}/core/lang.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> -- <snippet> — shell.sh, prereq.sh и lang.sh подключены, затем snippet
probe() {
    local -r sh_bin="$1"
    shift 2
    printf '. "%s"\n. "%s"\n. "%s"\n. "%s"\n%s\n' "${SHELL_SH}" "${PREREQ_SH}" "${QUIET_SH}" "${LANG_SH}" "$1" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${LANG_SH}'" "lang.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${LANG_SH}'" "shellcheck -s sh is clean for core/lang.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${LANG_SH}'" "core/lang.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${LANG_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare|local| \\[\\[ |=~'" "no shell-specific constructs in core/lang.sh" || true
}

test_behaviour() {
    local sh_bin sh_name v
    mkdir -p "${T}/d"; : > "${T}/empty"; printf x > "${T}/full"; ln -sf "${T}/full" "${T}/lnk"
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "$(probe "${sh_bin}" -- 'bs_is_empty ""; echo $?; bs_is_empty x; echo $?' | tr '\n' ' ')" "0 1 " "${sh_name}: bs_is_empty"
        eq "$(probe "${sh_bin}" -- 'bs_is_not_empty ""; echo $?; bs_is_not_empty x; echo $?' | tr '\n' ' ')" "1 0 " "${sh_name}: bs_is_not_empty"
        for v in "exists:${T}/d:0" "exists:${T}/none:1" "file:${T}/full:0" "file:${T}/d:1" "dir:${T}/d:0" "dir:${T}/full:1" \
                 "symlink:${T}/lnk:0" "symlink:${T}/full:1" "file_not_empty:${T}/full:0" "file_not_empty:${T}/empty:1" \
                 "readable:${T}/full:0" "readable:${T}/none:1" "writable:${T}/full:0" "writable:${T}/none:1"; do
            eq "$(probe "${sh_bin}" -- "bs_is_${v%%:*} '$(v2=${v#*:}; printf %s "${v2%:*}")'; echo \$?")" "${v##*:}" "${sh_name}: bs_is_${v%%:*} ${v#*:}"
        done
        eq "$(probe "${sh_bin}" -- "bs_is_executable /bin/sh; echo \$?; bs_is_executable '${T}/full'; echo \$?" | tr '\n' ' ')" "0 1 " "${sh_name}: bs_is_executable"
        for v in "0:0" "42:0" "007:0" "4x:1" "x4:1" "-1:1" "1.5:1" ":1" " 1:1"; do
            eq "$(probe "${sh_bin}" -- "bs_is_number '${v%%:*}'; echo \$?")" "${v##*:}" "${sh_name}: bs_is_number '${v%%:*}'"
        done
        eq "$(probe "${sh_bin}" -- 'bs_is_command ls; echo $?; bs_is_command no-such-cmd-xyz; echo $?' | tr '\n' ' ')" "0 1 " "${sh_name}: bs_is_command"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "$(probe "${sh_bin}" -- 'is::number 12; echo $?; is::number a; echo $?' | tr '\n' ' ')" "0 1 " "${sh_name}: is::number is an alias of bs_is_number"
        eq "$(probe "${sh_bin}" -- "is::dir '${T}/d'; echo \$?")" "0" "${sh_name}: is::dir is an alias of bs_is_dir"
    done
    # kernel in bash: the old names and the bash part (lib/compat/lang.sh) work after the real load
    eq "$(is::file_not_empty "${T}/full"; echo "rc=$?")" "rc=0" "kernel: is::file_not_empty works"
    eq "$(is::function is::file; echo "rc=$?")" "rc=0" "kernel: is::function (bash part) works"
    eq "$(str::upper abc)" "ABC" "kernel: str::upper (lib/compat/lang.sh) works"
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Behaviour in every shell / Поведение в каждой оболочке"; test_behaviour
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
