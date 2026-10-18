#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testposixtierunit.sh — bash does not take part in the `@shell posix` tier
# tests/unit/testposixtierunit.sh — в ярусе `@shell posix` bash не участвует
#
# Runs .agents/skills/bs-shell-abstraction/scripts/check_posix_tier.sh: every posix file parses in the
# non-bash shells, has no bash-only constructs, and the whole tier runs in dash with no bash in PATH.
# Запускает check_posix_tier.sh: каждый posix-файл разбирается в не-bash оболочках, не содержит
# bash-конструкций, а весь ярус работает в dash при отсутствии bash в PATH.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly CHECKER="${BS_PROJECT_ROOT}/.agents/skills/bs-shell-abstraction/scripts/check_posix_tier.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

test_real_tier() {
    local out rc=0
    out="$(bash "${CHECKER}" 2>&1)" || rc=$?
    testframework::assert_equal "0" "${rc}" "the real posix tier is clean (bash does not take part)" || true
    testframework::assert_command "grep -q 'bash в ярусе posix не участвует' <<< '${out//\'/}'" "the report says so" || true
    testframework::assert_command "test \"\$(bash '${CHECKER}' --list | wc -l)\" -ge 8" "the checker sees at least 8 posix files" || true
}

# Каждый posix-файл core/ имеет свой переносимый тест test<имя>portableunit.sh
# Every posix file of core/ has its own portable test test<name>portableunit.sh
test_every_core_file_has_a_test() {
    local f name missing=0
    while IFS= read -r f; do
        name="${f#core/}"; name="${name%.sh}"
        if [[ ! -f "${BS_PROJECT_ROOT}/tests/unit/test${name}portableunit.sh" ]]; then
            missing=$(( missing + 1 ))
            printf '    no portable test / нет переносимого теста: %s (tests/unit/test%sportableunit.sh)\n' "${f}" "${name}"
        fi
    done < <(bash "${CHECKER}" --list | grep '^core/')
    testframework::assert_equal "0" "${missing}" "every posix file of core/ has a test<name>portableunit.sh" || true
}

test_catches_violations() {
    local rc=0
    printf '#!/bin/sh\n# @shell posix — test\nif [[ -n "$1" ]]; then echo x; fi\n' > "${T}/bad_dbl.sh"
    bash "${CHECKER}" "${T}/bad_dbl.sh" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "1" "${rc}" "[[ ]] in a posix file is caught" || true
    rc=0
    printf '#!/bin/sh\n# @shell posix — test\necho ${BASH_VERSION}\n' > "${T}/bad_var.sh"
    bash "${CHECKER}" "${T}/bad_var.sh" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "1" "${rc}" "BASH_VERSION outside the layer is caught" || true
    rc=0
    printf '#!/bin/sh\n# @shell posix — test\nx=(a b)\n' > "${T}/bad_arr.sh"
    bash "${CHECKER}" "${T}/bad_arr.sh" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "1" "${rc}" "an array in a posix file is caught" || true
    rc=0
    printf '#!/bin/sh\n# @shell posix — test\necho clean\n' > "${T}/ok.sh"
    bash "${CHECKER}" "${T}/ok.sh" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "a clean posix file passes" || true
}

main() {
    T="$(mktemp -d)"
    testframework::section "Real tier / Настоящий ярус"; test_real_tier
    testframework::section "Tests exist / Тесты есть"; test_every_core_file_has_a_test
    testframework::section "Violations / Нарушения"; test_catches_violations
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
