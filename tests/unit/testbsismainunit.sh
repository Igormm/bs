#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testbsismainunit.sh — bs::is_main, bs::script_dir and utils::ensure_shell_version
# tests/unit/testbsismainunit.sh — bs::is_main, bs::script_dir и utils::ensure_shell_version
#
# One place knows how to tell "run" from "sourced" and where a file lives: the
# modules and examples call bs::is_main instead of copying BASH_SOURCE checks.
# Одно место знает, как отличить «запущен» от «подключён» и где лежит файл:
# модули и примеры вызывают bs::is_main, а не копируют проверки BASH_SOURCE.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

T=""
eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

main() {
    print_header "bs::is_main Unit Tests / Тесты bs::is_main"

    testframework::init
    T="$(mktemp -d)"

    testframework::section "bs::is_main"
    printf '#!/bin/bash\nsource "%s/bootstrap/bs.sh"\nif bs::is_main; then echo MAIN; else echo SOURCED; fi\n' "${BS_PROJECT_ROOT}" > "${T}/m.sh"
    eq "MAIN" "$(bash "${T}/m.sh")" "a file run directly is main"
    printf '#!/bin/bash\nsource "%s/m.sh" 2>&1\n' "${T}" > "${T}/host.sh"
    eq "SOURCED" "$(bash "${T}/host.sh" | tail -n 1)" "a file sourced by another is not main"
    eq "MAIN" "$(BS_RUN_SCRIPT="${T}/m.sh" bash -c "source '${T}/m.sh'" 2>&1)" "a file run by bs run (BS_RUN_SCRIPT) is main"
    eq "SOURCED" "$(BS_RUN_SCRIPT="${T}/other.sh" bash -c "source '${T}/m.sh'" 2>&1)" "a module sourced by the running script is not main"

    testframework::section "No copied guards / Нет копий охранника"
    local copies
    copies="$(grep -rlE 'BASH_EXECUTION_STRING:-.*BASH_SOURCE\[0\]' "${BS_PROJECT_ROOT}/lib" "${BS_PROJECT_ROOT}/core" "${BS_PROJECT_ROOT}/examples" 2>/dev/null | wc -l || true)"
    eq "0" "${copies}" "lib, core and examples use bs::is_main, not a copy of the guard"

    testframework::section "bs::script_dir"
    mkdir -p "${T}/sub"
    printf '#!/bin/bash\nsource "%s/bootstrap/bs.sh"\nf() { bs::script_dir; }\nf\n' "${BS_PROJECT_ROOT}" > "${T}/sub/d.sh"
    eq "$(cd "${T}/sub" && pwd -P)" "$(bash "${T}/sub/d.sh")" "bs::script_dir is the physical directory of the caller's file"

    testframework::section "init.sh and an inherited BS_INITIALIZED"
    eq "yes" "$(env -i HOME="${T}" PATH=/usr/bin:/bin BS_INITIALIZED=1 bash -c "source '${BS_PROJECT_ROOT}/bootstrap/init.sh' >/dev/null 2>&1; declare -F utils::strict >/dev/null && echo yes || echo no")" "a child that inherited BS_INITIALIZED=1 still loads the kernel"

    testframework::section "utils::ensure_shell_version"
    local out rc=0
    out="$(utils::ensure_shell_version 4 2>&1)" || rc=$?
    eq "0" "${rc}" "bash 4+ meets the requirement"
    eq "Shell bash meets version requirement (>= 4)" "${out}" "the message names the running shell"
    rc=0; utils::ensure_shell_version 99 >/dev/null 2>&1 || rc=$?
    eq "1" "${rc}" "a version that is too new fails with 1"

    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
