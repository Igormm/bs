#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testcalcportableunit.sh — core/calc.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testcalcportableunit.sh — core/calc.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/calc.sh is "@shell posix": the RPN calculator must give the same answers in every shell.
# core/calc.sh — "@shell posix": RPN-калькулятор обязан давать одинаковые ответы в любой оболочке.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly SHELL_SH="${BS_PROJECT_ROOT}/bootstrap/shell.sh"
readonly PREREQ_SH="${BS_PROJECT_ROOT}/core/prereq.sh"
readonly CALC_SH="${BS_PROJECT_ROOT}/core/calc.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <path> <snippet> — shell.sh, prereq.sh и calc.sh подключены, затем snippet; stdin — от вызывающего
probe() {
    local -r sh_bin="$1" path="$2" snippet="$3"
    printf '. "%s"\n. "%s"\n. "%s"\n%s\n' "${SHELL_SH}" "${PREREQ_SH}" "${CALC_SH}" "${snippet}" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="${path}" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${CALC_SH}'" "calc.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${CALC_SH}'" "shellcheck -s sh is clean for core/calc.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${CALC_SH}'" "core/calc.sh is declared @shell posix" || true
}

test_behaviour() {
    local sh_bin sh_name out
    utils::has dc || { printf '  skip: dc is not installed / dc не установлен\n'; return 0; }
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "14" "$(probe "${sh_bin}" /usr/bin:/bin 'bs_calc_eval "2 3 4 * +"')" "${sh_name}: RPN arithmetic"
        eq "3.1415929203" "$(probe "${sh_bin}" /usr/bin:/bin 'bs_calc_eval "10k 355 113 /"')" "${sh_name}: scale"
        eq "5" "$(probe "${sh_bin}" /usr/bin:/bin 'bs_calc_eval "2 3 + p"')" "${sh_name}: an explicit print is not doubled"
        eq "2 3 + p" "$(probe "${sh_bin}" /usr/bin:/bin 'bs_calc_autop "2 3 +"')" "${sh_name}: autop appends p"
        eq "2 3 + n" "$(probe "${sh_bin}" /usr/bin:/bin 'bs_calc_autop "2 3 + n"')" "${sh_name}: autop keeps n"
        eq "2 3 + # note" "$(probe "${sh_bin}" /usr/bin:/bin 'bs_calc_autop "2 3 + # note"')" "${sh_name}: autop leaves a comment alone"
        eq "14" "$(probe "${sh_bin}" /usr/bin:/bin 'bs_calc_main 2 3 4 "*" +')" "${sh_name}: bs_calc_main joins its arguments"
        out="$(probe "${sh_bin}" /usr/bin:/bin 'bs_calc_main --help' | head -n 1)"
        eq "BS calc — RPN calculator on dc / RPN-калькулятор на dc" "${out}" "${sh_name}: --help"
        # интерактивный режим: стек живёт между строками / interactive mode: the stack lives between lines
        out="$(printf '2 3\n+\n:q\n' | probe "${sh_bin}" /usr/bin:/bin 'bs_calc_interactive' | tail -n 2 | tr '\n' ' ')"
        eq "3 5 " "${out}" "${sh_name}: interactive session keeps the stack"
    done < <(testframework::posix_shells)
}

test_no_dc() {
    local sh_bin sh_name out rc
    # PATH без dc, но с printf: у mksh printf не встроен / PATH without dc but with printf: mksh has no builtin printf
    mkdir -p "${T}/empty"
    ln -sf "$(type -P printf)" "${T}/empty/printf"
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        rc=0; out="$(probe "${sh_bin}" "${T}/empty" 'bs_calc_main 1 2 +; echo "rc=$?"' )" || rc=$?
        [[ "${out}" == *"dc not found"* ]] && out="found-message rc=${out##*rc=}" || out="no-message ${out}"
        eq "found-message rc=1" "${out}" "${sh_name}: without dc — a message and exit 1"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    utils::has dc || { printf '  skip: dc is not installed / dc не установлен\n'; return 0; }
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "14" "$(probe "${sh_bin}" /usr/bin:/bin 'calc::eval "2 3 4 * +"')" "${sh_name}: calc::eval is an alias of bs_calc_eval"
    done
    # в ядре calc подключается по требованию (`bs calc`): подключаем сами / in the kernel calc loads on demand (`bs calc`): source it here
    # shellcheck disable=SC1090
    source "${CALC_SH}"
    eq "14" "$(calc::eval '2 3 4 * +')" "kernel: calc::eval works"
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Behaviour in every shell / Поведение в каждой оболочке"; test_behaviour
    testframework::section "No dc / Нет dc"; test_no_dc
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
