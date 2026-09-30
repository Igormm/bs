#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsystemutilsunit.sh — Unit tests for lib/system/utils module
# tests/unit/testsystemutilsunit.sh — Модульные тесты для модуля lib/system/utils

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Test module loading
test_module_loaded() {
    load "lib/system/utils"
    testframework::assert_true "${__SYSTEM_UTILS_SOURCED:-}" "Module loaded"
}

# Test get_ip_address returns a non-empty address
test_get_ip_address() {
    local ip
    ip="$(system::utils::get_ip_address || true)"
    testframework::assert_true "'${ip}' =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" "get_ip_address returns an IPv4 address"
}

# Test get_ip_address_for_interface on a real interface
test_interface_ip() {
    local iface ip
    iface="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
    if is::empty "${iface}"; then
        iface="$(ip -4 -o addr show 2>/dev/null | awk '$2 != "lo" {print $2; exit}')"
    fi
    if is::empty "${iface}"; then
        return 0
    fi
    ip="$(system::utils::get_ip_address_for_interface "${iface}" || true)"
    testframework::assert_true "'${ip}' =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" "get_ip_address_for_interface returns an IPv4 address for ${iface}"
}

# Test get_ip_address_for_interface with an unknown interface
test_missing_interface() {
    local out
    out="$(system::utils::get_ip_address_for_interface no_such_iface_xyz || true)"
    testframework::assert_equal "" "${out}" "get_ip_address_for_interface returns empty for an unknown interface"
}

main() {
    print_header "System Utils Unit Tests / Модульные тесты system/utils"

    testframework::init

    testframework::section "Module loading / Загрузка модуля"
    test_module_loaded

    testframework::section "IP detection / Определение IP"
    test_get_ip_address
    test_interface_ip
    test_missing_interface

    testframework::summary
}

main "$@"