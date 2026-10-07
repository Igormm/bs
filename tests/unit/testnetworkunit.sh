#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testnetworkunit.sh — unit tests for lib/system/network (data getters)
# tests/unit/testnetworkunit.sh — юнит-тесты lib/system/network (геттеры данных)
#
# Focus: the output-format contract — string default is preserved, json/xml are
# well-formed. Mutators (interface/static_ip/gateway/dns) are not covered here.
# Фокус: контракт форматов вывода — string по умолчанию сохранён, json/xml
# корректны. Мутаторы (interface/static_ip/gateway/dns) тут не проверяются.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/system/network"

main() {
    print_header "Network Unit Tests / Юнит-тесты network"
    testframework::init

    testframework::section "list_interfaces / список интерфейсов"
    local s
    s="$(system::network::list_interfaces)"
    testframework::assert_true "-n '${s}'" "string output non-empty"
    # no "iface:" prefix in the default string view
    testframework::assert_command "! printf '%s' '${s}' | grep -q 'iface:'" "string is bare names"

    local j
    j="$(BS_OUTPUT_FORMAT=json system::network::list_interfaces)"
    if command -v jq >/dev/null 2>&1; then
        testframework::assert_command "printf '%s' '${j}' | jq -e . >/dev/null" "json valid"
    else
        testframework::assert_true "'${j}' == '['* || '${j}' == '{'*" "json looks like array/object"
    fi

    local x
    x="$(BS_OUTPUT_FORMAT=xml system::network::list_interfaces)"
    if command -v xmllint >/dev/null 2>&1; then
        testframework::assert_command "printf '%s' '${x}' | xmllint --noout - 2>/dev/null" "xml valid"
    else
        testframework::assert_true "'${x}' == '<records>'*" "xml has records root"
    fi

    testframework::section "ip getter / геттер ip"
    local rc=0 ipv4
    ipv4="$(system::network::ip 2>/dev/null)" || rc=$?
    if (( rc == 0 )); then
        testframework::assert_true "'${ipv4}' =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" "string ip is a bare IPv4"
        testframework::assert_equal "{\"ip\":\"${ipv4}\"}" \
            "$(BS_OUTPUT_FORMAT=json system::network::ip)" "json ip object"
    else
        testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "no IPv4 → LIB_ERROR_FILE_NOT_FOUND"
    fi

    testframework::summary
}

main "$@"
