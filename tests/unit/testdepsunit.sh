#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testdepsunit.sh — Unit tests for core/deps module
# tests/unit/testdepsunit.sh — Модульные тесты для модуля core/deps

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Test deps::missing_tools collects missing package names
test_missing_tools_basic() {
    local -a missing=()
    deps::missing_tools missing bash sh
    testframework::assert_equal "0" "${#missing[@]}" "no missing tools for bash and sh"

    missing=()
    deps::missing_tools missing bash definitely-not-a-real-cmd-xyz
    testframework::assert_equal "1" "${#missing[@]}" "one missing tool detected"
    testframework::assert_equal "definitely-not-a-real-cmd-xyz" "${missing[0]}" "package defaults to command name"
}

# Test deps::missing_tools cmd:package mapping
test_missing_tools_package_map() {
    local -a missing=()
    deps::missing_tools missing definitely-not-a-real-cmd-xyz:some-package
    testframework::assert_equal "some-package" "${missing[0]}" "cmd:package maps to package name"
}

# Test deps::missing_tools alternatives (cmdA|cmdB)
test_missing_tools_alternatives() {
    local -a missing=()
    deps::missing_tools missing "definitely-not-a-real-cmd-xyz|bash:shell-pkg"
    testframework::assert_equal "0" "${#missing[@]}" "alternative satisfied by bash"

    missing=()
    deps::missing_tools missing "definitely-not-a-real-cmd-xyz|also-not-real-abc:shell-pkg"
    testframework::assert_equal "shell-pkg" "${missing[0]}" "unsatisfied alternatives reported as package"
}

# Test deps::missing_tools multi-package spec
test_missing_tools_multi_package() {
    local -a missing=()
    deps::missing_tools missing "definitely-not-a-real-cmd-xyz:pkg-one pkg-two"
    testframework::assert_equal "2" "${#missing[@]}" "space-separated packages both collected"
    testframework::assert_equal "pkg-two" "${missing[1]}" "second package name kept"
}

main() {
    print_header "Core Deps Unit Tests / Модульные тесты core/deps"

    testframework::init

    testframework::section "deps::missing_tools / Сбор отсутствующих инструментов"
    test_missing_tools_basic
    test_missing_tools_package_map
    test_missing_tools_alternatives
    test_missing_tools_multi_package

    testframework::summary
}

main "$@"
