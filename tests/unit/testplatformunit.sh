#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testplatformunit.sh — Unit tests for lib/platform/facts
# tests/unit/testplatformunit.sh — Модульные тесты для lib/platform/facts

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/platform/facts"

test_facts() {
    export PLATFORM_CACHE_FILE="$(mktemp -d)/bs-facts"

    testframework::assert_command "platform::get kernel | grep -qE '^(linux|darwin|freebsd)$'" "kernel is a known name"
    testframework::assert_command "platform::get arch | grep -q ." "arch present"
    testframework::assert_command "platform::get bash | grep -qE '^[0-9]'" "bash version present"
    testframework::assert_command "platform::get tier | grep -qE '^(core|gnu-linux|bsd)$'" "tier is valid"
    testframework::assert_command "platform::get repo | grep -q ." "repo derived"

    if [[ "$(uname -s)" == "Linux" ]]; then
        testframework::assert_equal "1" "$(platform::get procfs)" "procfs present on linux"
    fi

    # Дефолт / Default
    testframework::assert_equal "fallback" "$(platform::get not_a_fact fallback)" "platform::get default"

    # probe chain
    testframework::assert_command "platform::probe bash sh not-a-cmd | grep -q bash" "platform::probe returns first available"
    testframework::assert_false "platform::probe not-a-cmd-xyz" "platform::probe fails when none"

    rm -rf "$(dirname "${PLATFORM_CACHE_FILE}")"
}

test_cache() {
    local cache_dir
    cache_dir="$(mktemp -d)"
    export PLATFORM_CACHE_FILE="${cache_dir}/facts"

    platform::get repo >/dev/null
    testframework::assert_command "test -f '${cache_dir}/facts'" "cache file created"
    testframework::assert_command "grep -q '^kernel=' '${cache_dir}/facts'" "cache stores key=value"

    # Новый процесс читает из кэша / Fresh process reads the cache
    local tier1 tier2
    tier1="$(platform::get tier)"
    tier2="$(
        PLATFORM_CACHE_FILE="${cache_dir}/facts" bash -c '
            unset BS_INITIALIZED
            source /home/igor/bs/bootstrap/init.sh >/dev/null 2>&1
            export BS_SILENT=1
            load "lib/platform/facts"
            platform::get tier
        ' 2>/dev/null
    )"
    testframework::assert_equal "${tier1}" "${tier2}" "cache serves same facts to a new process"

    rm -rf "${cache_dir}"
}

main() {
    print_header "Platform Facts Unit Tests / Модульные тесты фактов платформы"

    testframework::init

    testframework::section "Facts / Факты"
    test_facts

    testframework::section "Cache / Кэш"
    test_cache

    testframework::summary
}

main "$@"