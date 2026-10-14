#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testpackagesunit.sh — Unit tests for lib/system/packages.sh
# tests/unit/testpackagesunit.sh — Модульные тесты для lib/system/packages.sh
#
# The package manager is a fake `apt` first in PATH: nothing is installed.
# Пакетный менеджер — заглушка `apt` первой в PATH: ничего не устанавливается.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
load "lib/system/packages"

main() {
    print_header "Packages Unit Tests / Модульные тесты packages"
    testframework::init

    local fake_bin rc
    fake_bin="$(mktemp -d)"
    cat > "${fake_bin}/apt" <<FAKE
#!/bin/sh
echo "\$*" >> "${fake_bin}/calls"
case "\$*" in
  *badpkg*) echo "E: Unable to locate package badpkg" >&2; exit 100 ;;
esac
exit 0
FAKE
    chmod +x "${fake_bin}/apt"
    local -r old_path="${PATH}"
    export PATH="${fake_bin}:${PATH}"

    testframework::section "install/remove report the manager's result / результат менеджера"
    rc=0; system::packages::install goodpkg >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "install of a good package succeeds"
    rc=0; system::packages::install goodpkg badpkg >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -ne 0" "a failed install returns an error"
    rc=0; system::packages::remove badpkg >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -ne 0" "a failed remove returns an error"
    rc=0; system::packages::remove goodpkg >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "remove of a good package succeeds"
    rc=0; system::packages::upgrade >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "upgrade succeeds"
    testframework::assert_command "grep -q '^install -y goodpkg badpkg$' '${fake_bin}/calls'" "all names were passed to the manager"

    testframework::section "arguments / аргументы"
    rc=0; system::packages::install >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -ne 0" "install without names is rejected"

    export PATH="${old_path}"
    rm -rf "${fake_bin}"
    testframework::summary
}

main "$@"
