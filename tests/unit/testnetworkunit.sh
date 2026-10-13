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

    testframework::section "status / статус (blob getter)"
    local st stj
    st="$(system::network::status lo)"
    if is::not_empty "${st}"; then
        testframework::assert_true "true" "status string non-empty"
        stj="$(BS_OUTPUT_FORMAT=json system::network::status lo)"
        if command -v jq >/dev/null 2>&1; then
            testframework::assert_command "printf '%s' '${stj}' | jq -e . >/dev/null" "status json valid"
        fi
    else
        testframework::assert_true "true" "status empty (no ip in env) — skipped"
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

    testframework::section "deterministic: fake ip / детерминированно: подставной ip"
    local fake_bin dns_tmp
    fake_bin="$(mktemp -d)"
    cat > "${fake_bin}/ip" <<'FAKE'
#!/bin/sh
case "$*" in
  "link show")
    echo "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536"
    echo "2: enp3s0: <BROADCAST,MULTICAST,UP> mtu 1500"
    echo "3: wlo1: <BROADCAST,MULTICAST,UP> mtu 1500"
    echo "4: veth12@if11: <BROADCAST,MULTICAST,UP> mtu 1500"
    ;;
  *bad0*) echo "Cannot find device bad0" >&2; exit 1 ;;
esac
exit 0
FAKE
    chmod +x "${fake_bin}/ip"
    local old_path="${PATH}"
    PATH="${fake_bin}:${PATH}"
    testframework::assert_equal "enp3s0 wlo1 veth12" "$(BS_OUTPUT_FORMAT=string system::network::list_interfaces | tr '\n' ' ' | sed 's/ $//')" "wlo1 is listed, only lo is skipped, @ifN suffix is cut"
    rc=0; system::network::interface bad0 up >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -ne 0" "a failed 'ip link set' is reported"
    rc=0; system::network::interface eth0 up >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "a successful 'ip link set' returns 0"
    PATH="${old_path}"
    rm -rf "${fake_bin}"

    testframework::section "prefix and dns / префикс и dns"
    testframework::assert_equal "255.255.255.252" "$(system::network::__netmask 30)" "netmask of /30"
    testframework::assert_equal "255.255.128.0" "$(system::network::__netmask 17)" "netmask of /17"
    testframework::assert_false "system::network::__netmask 33" "prefix 33 is invalid"
    dns_tmp="$(mktemp)"
    printf 'search example.org\nnameserver 9.9.9.9\noptions edns0\n' > "${dns_tmp}"
    BS_RESOLV_CONF="${dns_tmp}" FRAMEWORK_DRY_RUN=true system::network::dns 1.1.1.1 >/dev/null 2>&1
    testframework::assert_command "grep -q '^nameserver 9.9.9.9$' '${dns_tmp}'" "dry-run leaves resolv.conf untouched"
    BS_RESOLV_CONF="${dns_tmp}" system::network::dns 1.1.1.1 8.8.8.8 >/dev/null 2>&1
    testframework::assert_equal "search example.org|options edns0|nameserver 1.1.1.1|nameserver 8.8.8.8" "$(paste -sd'|' "${dns_tmp}")" "dns replaces nameservers and keeps other lines"
    rm -f "${dns_tmp}"

    testframework::summary
}

main "$@"
