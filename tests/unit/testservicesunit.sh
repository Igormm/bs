#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testservicesunit.sh — Unit tests for lib/system/services.sh
# tests/unit/testservicesunit.sh — Модульные тесты для lib/system/services.sh
#
# systemctl is replaced by a fake in PATH: the real services are never touched.
# systemctl подменён заглушкой в PATH: настоящие сервисы не затрагиваются.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
load "lib/system/services"

main() {
    print_header "Services Unit Tests / Модульные тесты services"
    testframework::init

    local fake_bin rc
    fake_bin="$(mktemp -d)"
    # The fake fails for the unit "bad.service" and logs every call
    # Заглушка падает для юнита "bad.service" и пишет каждый вызов в журнал
    cat > "${fake_bin}/systemctl" <<FAKE
#!/bin/sh
echo "\$*" >> "${fake_bin}/calls"
case "\$*" in
  *bad.service*) echo "Unit bad.service not found" >&2; exit 5 ;;
esac
exit 0
FAKE
    chmod +x "${fake_bin}/systemctl"
    local -r old_path="${PATH}"
    export PATH="${fake_bin}:${PATH}"

    testframework::section "failures are reported / сбои сообщаются"
    local verb
    for verb in start stop restart enable disable; do
        rc=0; "system::services::${verb}" bad.service >/dev/null 2>&1 || rc=$?
        testframework::assert_true "${rc} -ne 0" "${verb} of a failing unit returns an error"
        rc=0; "system::services::${verb}" ok.service >/dev/null 2>&1 || rc=$?
        testframework::assert_equal "0" "${rc}" "${verb} of a working unit succeeds"
    done
    testframework::assert_command "grep -q '^start ok.service' '${fake_bin}/calls'" "the command reached systemctl"

    testframework::section "status / статус"
    rc=0; system::services::status ok.service >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "status of an active unit is 0"
    rc=0; system::services::status bad.service >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "1" "${rc}" "status of an inactive unit is 1"
    rc=0; system::services::start "" >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -ne 0" "an empty name is rejected"

    export PATH="${old_path}"
    rm -rf "${fake_bin}"
    testframework::summary
}

main "$@"
