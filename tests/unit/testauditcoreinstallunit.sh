#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testauditcoreinstallunit.sh — audit regressions for install.sh
# tests/unit/testauditcoreinstallunit.sh — регрессии аудита для install.sh
#   1) uninstall removes the lib first and keeps the wrapper when that fails;
#   2) the "another install exists" frame is printed BEFORE the PATH setup
#      (in a terminal the PATH setup execs a fresh shell and ends the run).
#   Everything runs in mktemp -d with its own HOME/PATH/BS_SYSTEM_PREFIX.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

T=""
OUT=""
RC=0

sandbox() {
    T="$(mktemp -d)"
    mkdir -p "${T}/home" "${T}/sys" "${T}/tmpd"
}

drop_sandbox() {
    chmod -R u+w "${T}" 2>/dev/null || true
    rm -rf "${T:?}"
}

run_installer() {
    OUT="$(cd "${T}" && env -i HOME="${T}/home" PATH="/usr/bin:/bin" SHELL="/bin/bash" \
        BS_SYSTEM_PREFIX="${T}/sys" TMPDIR="${T}/tmpd" \
        bash "${BS_PROJECT_ROOT}/install.sh" "$@" 2>&1 </dev/null)" && RC=0 || RC=$?
}

test_uninstall_failure_keeps_wrapper() {
    sandbox
    run_installer --local
    local lib="${T}/home/.local/lib/bs" wrapper="${T}/home/.local/bin/bs"
    testframework::assert_command "test -f '${wrapper}' && test -d '${lib}'" "sandbox install is in place"
    chmod 555 "${lib}/core"
    run_installer --local uninstall
    testframework::assert_true "${RC} -ne 0" "uninstall that cannot remove the lib exits non-zero"
    testframework::assert_command "test -f '${wrapper}'" "the wrapper is kept when the lib could not be removed"
    testframework::assert_true "'${OUT}' == *'Uninstall failed'* || '${OUT}' == *'Удаление не выполнено'*" "the failure is explained"
    drop_sandbox
}

test_other_install_frame_precedes_path_setup() {
    sandbox
    mkdir -p "${T}/sys/lib/bs/bootstrap" "${T}/sys/bin"
    : > "${T}/sys/lib/bs/bs"
    : > "${T}/sys/lib/bs/bootstrap/init.sh"
    printf 'export BS_ROOT="%s"\n' "${T}/sys/lib/bs" > "${T}/sys/bin/bs"
    run_installer --local
    testframework::assert_equal "0" "${RC}" "local install next to a system install exits 0"
    local before="${OUT%%ANOTHER INSTALL EXISTS*}" path_step="${OUT%%In THIS terminal run*}"
    testframework::assert_true "'${OUT}' == *'ANOTHER INSTALL EXISTS'*" "the other-install frame is printed"
    testframework::assert_true "${#before} -lt ${#path_step}" "the frame comes before the PATH instructions"
    drop_sandbox
}

main() {
    print_header "Audit: install.sh / Аудит: install.sh"
    testframework::init
    testframework::section "Uninstall order / Порядок удаления"
    test_uninstall_failure_keeps_wrapper
    testframework::section "Report order / Порядок сообщений"
    test_other_install_frame_precedes_path_setup
    testframework::summary
}

main "$@"
