#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testbscliunit.sh — Unit tests for the bs CLI entry point
# tests/unit/testbscliunit.sh — Модульные тесты точки входа bs CLI
#
# Этот файл содержит unit тесты для интерфейса командной строки bs.
# This file contains unit tests for the bs command-line interface.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly BS_BIN="${BS_PROJECT_ROOT}/bs"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Load BS bootstrap so utils::* helpers are available.
# Подключаем bootstrap BS, чтобы были доступны хелперы utils::*.
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

main() {
    print_header "bs CLI Unit Tests / Модульные тесты bs CLI"
    testframework::init

    testframework::section "Help output / Вывод справки"

    local out rc
    rc=0
    out=$("${BS_BIN}" --help 2>&1) || rc=$?
    testframework::assert_equal "0" "${rc:-0}" "bs --help exits 0"
    if echo "${out}" | grep -q "Modules / Модули"; then
        testframework::assert_true "true" "bs --help shows grouped commands"
    else
        testframework::assert_true "false" "bs --help shows grouped commands"
    fi

    testframework::section "Command help / Справка по команде"

    rc=0
    out=$("${BS_BIN}" help build 2>&1) || rc=$?
    testframework::assert_equal "0" "${rc:-0}" "bs help build exits 0"
    if echo "${out}" | grep -q "Usage: bs build"; then
        testframework::assert_true "true" "bs help build shows build usage"
    else
        testframework::assert_true "false" "bs help build shows build usage"
    fi

    rc=0
    utils::quiet_err "${BS_BIN}" help nonexistent_command || rc=$?
    testframework::assert_true "$rc -ne 0" "bs help unknown exits non-zero"

    testframework::section "Version / Версия"

    rc=0
    out=$("${BS_BIN}" version 2>&1) || rc=$?
    testframework::assert_equal "0" "${rc:-0}" "bs version exits 0"
    if echo "${out}" | grep -Eq "[0-9]+\.[0-9]+"; then
        testframework::assert_true "true" "bs version prints a version"
    else
        testframework::assert_true "false" "bs version prints a version"
    fi

    testframework::summary
}

main "$@"
