#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testquietportableunit.sh — core/quiet.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testquietportableunit.sh — core/quiet.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/quiet.sh is "@shell posix": utils_has / utils_quiet / utils_quiet_err /
# utils_ignore / utils_attempt must give the same answers in every shell.
# core/quiet.sh — "@shell posix": эти пять функций обязаны давать одинаковые
# ответы в любой оболочке.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly SHELL_SH="${BS_PROJECT_ROOT}/bootstrap/shell.sh"
readonly PREREQ_SH="${BS_PROJECT_ROOT}/core/prereq.sh"
readonly QUIET_SH="${BS_PROJECT_ROOT}/core/quiet.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> -- <snippet> — shell.sh, prereq.sh и quiet.sh подключены, затем snippet
probe() {
    local -r sh_bin="$1"
    shift 2
    printf '. "%s"\n. "%s"\n. "%s"\n%s\n' "${SHELL_SH}" "${PREREQ_SH}" "${QUIET_SH}" "$1" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${QUIET_SH}'" "quiet.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${QUIET_SH}'" "shellcheck -s sh is clean for core/quiet.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${QUIET_SH}'" "core/quiet.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${QUIET_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare|local| \\[\\[ |is::empty'" "no shell-specific constructs in core/quiet.sh" || true
}

test_behaviour() {
    local sh_bin sh_name out
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "$(probe "${sh_bin}" -- 'utils_has ls && echo y')" "y" "${sh_name}: utils_has finds ls"
        eq "$(probe "${sh_bin}" -- 'utils_has no-such-cmd-xyz || echo n')" "n" "${sh_name}: utils_has misses a missing command"
        eq "$(probe "${sh_bin}" -- 'utils_quiet sh -c "echo out; echo err >&2; exit 3"; echo "rc=$?"')" "rc=3" "${sh_name}: utils_quiet hides all output, keeps rc"
        out="$(probe "${sh_bin}" -- 'utils_quiet_err sh -c "echo out; echo err >&2; exit 2"; echo "rc=$?"' | tr '\n' ' ')"
        eq "${out}" "out rc=2 " "${sh_name}: utils_quiet_err keeps stdout and rc, hides stderr"
        eq "$(probe "${sh_bin}" -- 'utils_ignore false; echo "rc=$?"')" "rc=0" "${sh_name}: utils_ignore always succeeds"
        out="$(probe "${sh_bin}" -- 'utils_attempt sh -c "echo out; echo err >&2; exit 1"; echo "rc=$?"' | tr '\n' ' ')"
        eq "${out}" "out rc=0 " "${sh_name}: utils_attempt keeps stdout, hides stderr, succeeds"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "$(probe "${sh_bin}" -- 'utils::has ls && echo y')" "y" "${sh_name}: utils::has is an alias of utils_has"
        eq "$(probe "${sh_bin}" -- 'utils::ignore false; echo "rc=$?"')" "rc=0" "${sh_name}: utils::ignore is an alias of utils_ignore"
    done
    # kernel in bash: the old names still work after the real load
    eq "$(utils::has ls && echo y)" "y" "kernel: utils::has works"
    eq "$(utils::attempt false; echo "rc=$?")" "rc=0" "kernel: utils::attempt works"
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
