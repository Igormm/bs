#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testauditcoreuninstallunit.sh — audit regressions for `bs uninstall`
# tests/unit/testauditcoreuninstallunit.sh — регрессии аудита для `bs uninstall`
#   1) a failed removal must keep the wrapper (a half-removed install without
#      a command is unrecoverable); 2) a symlinked lib dir: the wrapper that
#      names the symlink is still "ours" and the dangling link is removed.
#   Everything runs in mktemp -d with its own HOME/PATH/BS_SYSTEM_PREFIX.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
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
    mkdir -p "${T}/home" "${T}/sys" "${T}/tmpd" "${T}/pfx/bin" "${T}/pfx/lib"
}

drop_sandbox() {
    chmod -R u+w "${T}" 2>/dev/null || true
    rm -rf "${T:?}"
}

make_install() {
    local -r dir="$1"
    mkdir -p "${dir}/core" "${dir}/lib" "${dir}/bootstrap"
    printf '#!/usr/bin/env bash\n' > "${dir}/bs"
    printf '#!/usr/bin/env bash\n' > "${dir}/bootstrap/init.sh"
    printf 'export BS_VERSION="9.9.9"\n' > "${dir}/core/version.sh"
    printf 'x\n' > "${dir}/lib/mod.sh"
    printf 'mode=custom\n' > "${dir}/.install"
}

make_wrapper() {
    printf '#!/usr/bin/env bash\nexport BS_ROOT="%s"\nexec "${BS_ROOT}/bs" "$@"\n' "$2" > "$1"
    chmod +x "$1"
}

run_uninstall() {
    OUT="$(cd "${T}" && env -u BS_ROOT -u BS_HOME -u BS_INITIALIZED -u SUDO_USER \
        HOME="${T}/home" PATH="/usr/bin:/bin" BS_SYSTEM_PREFIX="${T}/sys" TMPDIR="${T}/tmpd" \
        "${TEST_BASH}" "${BS_PROJECT_ROOT}/bs" uninstall "$@" 2>&1 </dev/null)" && RC=0 || RC=$?
}

test_failed_removal_keeps_wrapper() {
    if testframework::is_root; then
        testframework::skip "failed removal keeps the wrapper" "running as root (chmod 555 does not stop root)"
        return 0
    fi
    sandbox
    local lib="${T}/pfx/lib/bs" wrapper="${T}/pfx/bin/bs"
    make_install "${lib}"
    make_wrapper "${wrapper}" "${lib}"
    chmod 555 "${lib}/core"   # files inside core/ cannot be unlinked
    run_uninstall --lib "${lib}"
    testframework::assert_equal "1" "${RC}" "failed removal exits 1"
    testframework::assert_command "test -f '${wrapper}'" "the wrapper is kept when the directory could not be removed"
    testframework::assert_true "'${OUT}' == *'removal failed'* || '${OUT}' == *'удаление не удалось'*" "the failure is reported"
    drop_sandbox
}

test_symlinked_lib_is_removed_with_its_wrapper() {
    sandbox
    local lib="${T}/pfx/lib/bs" wrapper="${T}/pfx/bin/bs" real="${T}/real"
    make_install "${real}"
    ln -s "${real}" "${lib}"
    make_wrapper "${wrapper}" "${lib}"
    run_uninstall --lib "${lib}"
    testframework::assert_equal "0" "${RC}" "uninstall of a symlinked lib exits 0"
    testframework::assert_command "test ! -e '${real}'" "the real directory is removed"
    testframework::assert_command "test ! -L '${lib}'" "the dangling symlink is removed"
    testframework::assert_command "test ! -e '${wrapper}'" "the wrapper that names the symlink is removed"
    drop_sandbox
}

test_plain_uninstall_unchanged() {
    sandbox
    local lib="${T}/pfx/lib/bs" wrapper="${T}/pfx/bin/bs"
    make_install "${lib}"
    make_wrapper "${wrapper}" "${lib}"
    run_uninstall --lib "${lib}"
    testframework::assert_equal "0" "${RC}" "plain uninstall exits 0"
    testframework::assert_command "test ! -e '${lib}' && test ! -e '${wrapper}'" "lib and wrapper are gone"
    drop_sandbox
}

main() {
    print_header "Audit: bs uninstall / Аудит: bs uninstall"
    testframework::init
    testframework::section "Order and symlinks / Порядок и симлинки"
    test_failed_removal_keeps_wrapper
    test_symlinked_lib_is_removed_with_its_wrapper
    test_plain_uninstall_unchanged
    testframework::summary
}

main "$@"
