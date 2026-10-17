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

# Оболочки для проверки: имя; "busybox ash" — апплет / shells to check; "busybox ash" is an applet
readonly -a TEST_SHELLS=("bash" "zsh" "dash" "busybox ash" "ksh" "mksh")

# probe <shell...> -- <snippet> — shell.sh, prereq.sh и quiet.sh подключены, затем snippet
probe() {
    local -a launcher=()
    while [[ "$1" != "--" ]]; do launcher+=("$1"); shift; done
    shift
    printf '. "%s"\n. "%s"\n. "%s"\n%s\n' "${SHELL_SH}" "${PREREQ_SH}" "${QUIET_SH}" "$1" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${launcher[@]}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

# have <shell words> — установлена ли оболочка / is the shell installed
have() { command -v "${1%% *}" >/dev/null 2>&1; }

test_parses_and_lints() {
    local sh_name
    for sh_name in "${TEST_SHELLS[@]}"; do
        have "${sh_name}" || { printf '  skip: %s is not installed / не установлен\n' "${sh_name}"; continue; }
        testframework::assert_command "${sh_name} -n '${QUIET_SH}'" "quiet.sh parses in ${sh_name}" || true
    done
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${QUIET_SH}'" "shellcheck -s sh is clean for core/quiet.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${QUIET_SH}'" "core/quiet.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${QUIET_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare|local| \\[\\[ |is::empty'" "no shell-specific constructs in core/quiet.sh" || true
}

test_behaviour() {
    local sh_name out
    for sh_name in "${TEST_SHELLS[@]}"; do
        have "${sh_name}" || continue
        # IFS строгий в скриптах bs: слова делим явно / IFS is strict in bs scripts: split the words explicitly
        local -a words=()
        IFS=' ' read -ra words <<< "${sh_name}"
        set -- "${words[@]}"
        eq "$(probe "$@" -- 'utils_has ls && echo y')" "y" "${sh_name}: utils_has finds ls"
        eq "$(probe "$@" -- 'utils_has no-such-cmd-xyz || echo n')" "n" "${sh_name}: utils_has misses a missing command"
        eq "$(probe "$@" -- 'utils_quiet sh -c "echo out; echo err >&2; exit 3"; echo "rc=$?"')" "rc=3" "${sh_name}: utils_quiet hides all output, keeps rc"
        out="$(probe "$@" -- 'utils_quiet_err sh -c "echo out; echo err >&2; exit 2"; echo "rc=$?"' | tr '\n' ' ')"
        eq "${out}" "out rc=2 " "${sh_name}: utils_quiet_err keeps stdout and rc, hides stderr"
        eq "$(probe "$@" -- 'utils_ignore false; echo "rc=$?"')" "rc=0" "${sh_name}: utils_ignore always succeeds"
        out="$(probe "$@" -- 'utils_attempt sh -c "echo out; echo err >&2; exit 1"; echo "rc=$?"' | tr '\n' ' ')"
        eq "${out}" "out rc=0 " "${sh_name}: utils_attempt keeps stdout, hides stderr, succeeds"
    done
}

test_aliases() {
    local sh_name
    for sh_name in bash zsh; do
        have "${sh_name}" || continue
        eq "$(probe "${sh_name}" -- 'utils::has ls && echo y')" "y" "${sh_name}: utils::has is an alias of utils_has"
        eq "$(probe "${sh_name}" -- 'utils::ignore false; echo "rc=$?"')" "rc=0" "${sh_name}: utils::ignore is an alias of utils_ignore"
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
