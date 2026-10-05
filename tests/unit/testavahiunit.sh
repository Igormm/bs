#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testavahiunit.sh — Unit tests for lib/network/avahi
# tests/unit/testavahiunit.sh — Модульные тесты для lib/network/avahi
#
# Tests mDNS/Avahi helpers: hostname discovery and availability predicates.
# Тестирует вспомогательные функции mDNS/Avahi: определение имени хоста и
# предикаты доступности.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

main() {
    print_header "Avahi Unit Tests / Модульные тесты Avahi"

    testframework::init

    # Тест 1: Проверка загрузки модуля
    testframework::section "Module Loading / Загрузка модуля"
    load "lib/network/avahi"
    testframework::assert_true "${LIB_NETWORK_AVAHI_LOADED:-}" "Avahi module loaded"

    # Тест 2: .local-имя хоста всегда заканчивается на .local
    testframework::section "Hostname Local / .local-имя хоста"
    local hostname_local
    hostname_local="$(network::avahi::hostname_local)"
    if [[ "${hostname_local}" == *.local ]]; then
        testframework::assert_true "true" "hostname_local ends with .local"
    else
        testframework::assert_true "false" "hostname_local '${hostname_local}' ends with .local"
    fi
    testframework::assert_command "is::not_empty '${hostname_local}'" \
        "hostname_local is not empty"

    # Тест 3: available — чистый предикат, возвращает 0 или 1
    testframework::section "Availability / Доступность"
    local avail_rc=0
    network::avahi::available || avail_rc=$?
    testframework::assert_true "${avail_rc} -eq 0 || ${avail_rc} -eq 1" \
        "available returns boolean (0 or 1)"

    # Тест 4: running — чистый предикат, возвращает 0 или 1
    testframework::section "Daemon State / Состояние демона"
    local running_rc=0
    network::avahi::running || running_rc=$?
    testframework::assert_true "${running_rc} -eq 0 || ${running_rc} -eq 1" \
        "running returns boolean (0 or 1)"

    testframework::summary
}

main "$@"
