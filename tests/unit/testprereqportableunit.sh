#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testprereqportableunit.sh — core/prereq.sh as POSIX code under dash, zsh and bash
# tests/unit/testprereqportableunit.sh — core/prereq.sh как POSIX-код под dash, zsh и bash
#
# core/prereq.sh is declared "@shell posix": besides parsing in every shell it
# must behave the same there. Each shell runs a probe in a temporary HOME under env -i.
# core/prereq.sh объявлен "@shell posix": кроме разбора в каждой оболочке он обязан
# и вести себя одинаково. Каждая оболочка исполняет пробу во временном HOME под env -i.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly SHELL_SH="${BS_PROJECT_ROOT}/bootstrap/shell.sh"
readonly PREREQ_SH="${BS_PROJECT_ROOT}/core/prereq.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — shell.sh и prereq.sh подключены, затем snippet
probe() {
    local -r sh_bin="$1" snippet="$2"
    printf '. "%s"\n. "%s"\n%s\n' "${SHELL_SH}" "${PREREQ_SH}" "${snippet}" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

# Оболочки, которые есть на машине (bash — всегда)
# Shells present on the machine (bash is always there)
installed_shells() {
    testframework::posix_shells
}

test_parses_and_lints() {
    local bin
    while IFS= read -r bin; do
        testframework::assert_command "'${bin}' -n '${PREREQ_SH}'" "prereq.sh parses in ${bin##*/}" || true
    done < <(installed_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${PREREQ_SH}'" "shellcheck -s sh is clean for core/prereq.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${PREREQ_SH}'" "core/prereq.sh is declared @shell posix" || true
    testframework::assert_command "! grep -E 'BASH_|ZSH_|FUNCNAME|\\\$SHELL' '${PREREQ_SH}' | grep -v '^#'" "no shell variables in core/prereq.sh" || true
}

test_guard_per_shell() {
    local bin name
    while IFS= read -r bin; do
        name="${bin##*/}"
        eq "0 1 0 1" "$(probe "${bin}" 'bs_guard PX_A; a=$?; bs_guard PX_A; b=$?; bs_guard_loaded PX_A; c=$?; bs_guard_loaded PX_NOPE; d=$?; echo "$a $b $c $d"')" "${name}: bs_guard first/repeat, bs_guard_loaded yes/no"
        eq "0 1" "$(probe "${bin}" 'bs_guard px_lower; a=$?; bs_guard PX_LOWER; echo "$a $?"')" "${name}: the name is case-insensitive (upper-cased)"
        eq "2 1" "$(probe "${bin}" 'bs_guard "a/b"; a=$?; bs_guard_loaded "a b"; echo "$a $?"')" "${name}: an invalid name is refused, never eval'ed"
        eq "yes" "$(probe "${bin}" 'bs_guard PX_RO; (unset __PX_RO_SOURCED) 2>/dev/null && echo no || echo yes')" "${name}: the mark is readonly"
    done < <(installed_shells 2>/dev/null)
}

test_namespaced_aliases() {
    local bin name
    while IFS= read -r bin; do
        name="${bin##*/}"
        case "${name}" in
            bash|zsh) eq "0 1" "$(probe "${bin}" 'bs::guard PX_NS; a=$?; bs::guard PX_NS; echo "$a $?"; bs::guard_loaded PX_NS')" "${name}: bs::guard is an alias of bs_guard" ;;
            *)        eq "absent" "$(probe "${bin}" 'type bs::guard >/dev/null 2>&1 && echo present || echo absent')" "${name}: no bs::guard (the name is not valid here)" ;;
        esac
    done < <(installed_shells 2>/dev/null)
}

test_source_relative_per_shell() {
    local bin name
    mkdir -p "${T}/fx"
    printf 'FX_A=loaded\nbs_source_relative nested.sh\n' > "${T}/fx/a.sh"
    printf 'FX_NESTED=yes\n' > "${T}/fx/nested.sh"
    printf 'FX_B=loaded\n' > "${T}/fx/b.sh"
    printf 'false\n' > "${T}/fx/fail.sh"
    while IFS= read -r bin; do
        name="${bin##*/}"
        [[ "${name}" == bash ]] && continue   # в bash база — стек вызовов, см. testprerequnit.sh / bash takes the call stack, see testprerequnit.sh
        eq "loaded yes ${T}/fx/main.sh" "$(probe "${bin}" "BS_CURRENT_FILE='${T}/fx/main.sh'; bs_source_relative a.sh; echo \"\$FX_A \$FX_NESTED \$BS_CURRENT_FILE\"")" "${name}: relative source, nested call, BS_CURRENT_FILE restored"
        eq "1" "$(probe "${bin}" "BS_CURRENT_FILE='${T}/fx/main.sh'; bs_source_relative nested.sh fail.sh; echo \$?")" "${name}: the status of the last file is returned"
    done < <(installed_shells 2>/dev/null)
    # bash: база — каталог вызывающего файла; через явный bs_source_relative_from
    # bash: the base is the caller's directory; via the explicit bs_source_relative_from
    eq "loaded" "$(probe "$(command -v bash)" "bs_source_relative_from '${T}/fx/main.sh' b.sh; echo \"\$FX_B\"" 2>&1 | tail -1)" "bash: bs_source_relative_from sources relative to the base file"
}

main() {
    print_header "core/prereq portable Unit Tests / Модульные тесты core/prereq в разных оболочках"
    testframework::init
    T="$(mktemp -d)"
    trap 'rm -rf "${T}"' EXIT
    mkdir -p "${T}/h"

    testframework::section "Parse and lint / Разбор и линтер"
    test_parses_and_lints
    testframework::section "bs_guard per shell / bs_guard по оболочкам"
    test_guard_per_shell
    testframework::section "bs::* aliases / Псевдонимы bs::*"
    test_namespaced_aliases
    testframework::section "bs_source_relative per shell / bs_source_relative по оболочкам"
    test_source_relative_per_shell

    testframework::summary
}

main "$@"
