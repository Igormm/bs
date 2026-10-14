#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testguardportableunit.sh — core/guard.sh as POSIX code under dash, zsh and bash
# tests/unit/testguardportableunit.sh — core/guard.sh как POSIX-код под dash, zsh и bash
#
# core/guard.sh is "@shell posix": it must parse and behave the same in every shell.
# core/guard.sh — "@shell posix": он обязан разбираться и вести себя одинаково везде.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly SHELL_SH="${BS_PROJECT_ROOT}/bootstrap/shell.sh"
readonly GUARD_SH="${BS_PROJECT_ROOT}/core/guard.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — shell.sh подключён, затем snippet
probe() {
    local -r sh_bin="$1" snippet="$2"
    printf '. "%s"\n%s\n' "${SHELL_SH}" "${snippet}" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

installed_shells() {
    local n
    for n in bash zsh dash; do
        command -v "${n}" 2>/dev/null || printf 'skip: %s is not installed / не установлен\n' "${n}" >&2
    done
}

test_parses_and_lints() {
    local bin
    while IFS= read -r bin; do
        testframework::assert_command "'${bin}' -n '${GUARD_SH}'" "guard.sh parses in ${bin##*/}" || true
    done < <(installed_shells 2>/dev/null)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${GUARD_SH}'" "shellcheck -s sh is clean for core/guard.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${GUARD_SH}'" "core/guard.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${GUARD_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare|\\[\\['" "no shell-specific constructs in core/guard.sh" || true
}

test_loads_prereq_per_shell() {
    local bin name
    while IFS= read -r bin; do
        name="${bin##*/}"
        eq "1 0 1" "$(probe "${bin}" "BS_ROOT='${BS_PROJECT_ROOT}'; . '${GUARD_SH}'; echo \"\${__GUARD_SOURCED:-}\"; bs_guard GP_X; echo \$?; bs_guard GP_X; echo \$?" | tr '\n' ' ' | sed 's/ $//')" "${name}: sourcing guard.sh pulls in prereq.sh (BS_ROOT), bs_guard works" || true
        eq "1 0" "$(probe "${bin}" "BS_ROOT=''; BS_CURRENT_FILE='${BS_PROJECT_ROOT}/core/guard.sh'; . '${GUARD_SH}'; echo \"\${__GUARD_SOURCED:-}\"; bs_guard GP_Y; echo \$?" | tr '\n' ' ' | sed 's/ $//')" "${name}: without BS_ROOT the directory comes from BS_CURRENT_FILE" || true
        eq "0 1" "$(probe "${bin}" "BS_ROOT='${BS_PROJECT_ROOT}'; . '${GUARD_SH}'; . '${GUARD_SH}'; echo \$?; echo \"\${__GUARD_SOURCED:-}\"" | tr '\n' ' ' | sed 's/ $//')" "${name}: a second source is a no-op" || true
        eq "readonly" "$(probe "${bin}" "BS_ROOT='${BS_PROJECT_ROOT}'; . '${GUARD_SH}'; (unset __GUARD_SOURCED) 2>/dev/null && echo writable || echo readonly")" "${name}: __GUARD_SOURCED is readonly" || true
        eq "failed" "$(probe "${bin}" "BS_ROOT=''; BS_CURRENT_FILE=''; . '${GUARD_SH}' >/dev/null 2>&1 && echo loaded || echo failed")" "${name}: neither BS_ROOT nor BS_CURRENT_FILE is an error, not a wrong path" || true
    done < <(installed_shells 2>/dev/null)
}

main() {
    print_header "core/guard portable Unit Tests / Модульные тесты core/guard в разных оболочках"
    testframework::init
    T="$(mktemp -d)"
    trap 'rm -rf "${T}"' EXIT
    mkdir -p "${T}/h"

    testframework::section "Parse and lint / Разбор и линтер"
    test_parses_and_lints
    testframework::section "guard.sh per shell / guard.sh по оболочкам"
    test_loads_prereq_per_shell

    testframework::summary
}

main "$@"
