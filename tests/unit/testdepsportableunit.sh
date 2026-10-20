#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testdepsportableunit.sh — core/deps.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testdepsportableunit.sh — core/deps.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/deps.sh is "@shell posix": the command checks, the @optdeps parsing and the missing-tool
# collection (into a data-layer array) must give the same answers in every shell.
# core/deps.sh — "@shell posix": проверки команд, разбор @optdeps и сбор недостающих инструментов
# (в массив слоя данных) обязаны давать одинаковые ответы в любой оболочке.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly DEPS_SH="${BS_PROJECT_ROOT}/core/deps.sh"
readonly NOPE="definitely-not-a-real-cmd-xyz"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — всё нужное подключено; BS_ROOT указывает на фиктивный корень с модулем lib/fake/mod.sh
probe() {
    local -r sh_bin="$1" snippet="$2"
    local f
    : > "${T}/probe.sh"
    for f in bootstrap/shell.sh core/prereq.sh core/const.sh core/logger.sh core/quiet.sh core/data.sh core/utils.sh core/deps.sh; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "${snippet}" >> "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" BS_ROOT="${T}/root" BS_LOG_TIMESTAMP=false "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${DEPS_SH}'" "deps.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${DEPS_SH}'" "shellcheck -s sh is clean for core/deps.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${DEPS_SH}'" "core/deps.sh is declared @shell posix" || true
}

test_behaviour() {
    local sh_bin sh_name
    mkdir -p "${T}/root/lib/fake"
    printf '#!/usr/bin/env bs\n# @optdeps  sh,  %s   ls\n' "${NOPE}" > "${T}/root/lib/fake/mod.sh"
    printf '#!/usr/bin/env bs\n# no optional deps here\n' > "${T}/root/lib/fake/plain.sh"
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_deps_has ls; echo rc=$?')" "${sh_name}: has finds ls"
        eq "rc=1" "$(probe "${sh_bin}" "bs_deps_has ${NOPE}; echo rc=\$?")" "${sh_name}: has misses a missing command"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_deps_has "" 2>/dev/null; echo rc=$?')" "${sh_name}: has with no name is 1"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_deps_require ls; echo rc=$?')" "${sh_name}: require of an available command is 0"
        eq "[ERROR] custom message|rc=203" "$(probe "${sh_bin}" "bs_deps_require ${NOPE} 'custom message'; echo rc=\$?" | tr '\n' '|' | sed 's/|$//')" "${sh_name}: require reports with its own message"
        eq "[ERROR] Required dependency not found: ${NOPE}" "$(probe "${sh_bin}" "bs_deps_require ${NOPE}; true" | head -n 1)" "${sh_name}: require reports the default message"
        eq "sh ls" "$(probe "${sh_bin}" 'bs_deps_parse_optdeps lib/fake/mod || true' | sed "s/ ${NOPE}//")" "${sh_name}: parse_optdeps normalizes the list"
        eq "${NOPE}|rc=1" "$(probe "${sh_bin}" 'bs_deps_list_missing lib/fake/mod; echo rc=$?' | tr '\n' '|' | sed 's/|$//')" "${sh_name}: list_missing names what is missing"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_deps_list_missing lib/fake/plain; echo rc=$?')" "${sh_name}: a module with no @optdeps is 0"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_deps_check_module lib/fake/mod 2>/dev/null; echo rc=$?')" "${sh_name}: check_module warns and returns 1"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_deps_check_module lib/fake/plain; echo rc=$?')" "${sh_name}: check_module is 0 when satisfied"
        eq "pkg-one|pkg-two" "$(probe "${sh_bin}" "bs_deps_missing_tools m ${NOPE}:'pkg-one pkg-two'; bs_arr_join m '|'")" "${sh_name}: missing_tools takes several packages"
        eq "${NOPE}" "$(probe "${sh_bin}" "bs_deps_missing_tools m ${NOPE}; bs_arr_join m '|'")" "${sh_name}: the package defaults to the command"
        eq "0" "$(probe "${sh_bin}" "bs_deps_missing_tools m \"${NOPE}|sh:shell-pkg\"; bs_arr_len m")" "${sh_name}: one available alternative is enough"
        eq "shell-pkg" "$(probe "${sh_bin}" "bs_deps_missing_tools m \"${NOPE}|also-${NOPE}:shell-pkg\"; bs_arr_join m '|'")" "${sh_name}: all alternatives missing gives the package"
        eq "a|b" "$(probe "${sh_bin}" "bs_deps_missing_tools m ${NOPE}:a ls ${NOPE}2:b; bs_arr_join m '|'")" "${sh_name}: several specs"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "rc=0" "$(probe "${sh_bin}" 'deps::has ls; echo rc=$?')" "${sh_name}: deps::has is an alias of bs_deps_has"
        eq "${NOPE}|rc=1" "$(probe "${sh_bin}" 'deps::list_missing lib/fake/mod; echo rc=$?' | tr '\n' '|' | sed 's/|$//')" "${sh_name}: deps::list_missing is an alias"
    done
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
