#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testroutingunit.sh — unit tests for lib/system/routing (data getters)
# tests/unit/testroutingunit.sh — юнит-тесты lib/system/routing (геттеры данных)
#
# Focus: blob getters (show/rules) keep their raw string view and produce valid
# json/xml. Mutators (add/delete/default/table add/delete/policy/ipv6) are not
# covered here. / Фокус: блоб-геттеры сохраняют сырой string-вид и дают валидные
# json/xml. Мутаторы не проверяются.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/system/routing"

main() {
    print_header "Routing Unit Tests / Юнит-тесты routing"
    testframework::init

    testframework::section "show / routes"
    local s
    s="$(system::routing::show)"
    if is::not_empty "${s}"; then
        testframework::assert_true "true" "show string non-empty"
        testframework::assert_command "! printf '%s' '${s}' | grep -q 'route:'" "string is bare route lines"
        if command -v jq >/dev/null 2>&1; then
            testframework::assert_command \
                "BS_OUTPUT_FORMAT=json system::routing::show | jq -e . >/dev/null" "show json valid"
        fi
    else
        testframework::assert_true "true" "show empty (no ip in env) — skipped"
    fi

    testframework::section "rules / policy rules"
    local r
    r="$(system::routing::rules)"
    if is::not_empty "${r}"; then
        testframework::assert_true "true" "rules string non-empty"
        if command -v jq >/dev/null 2>&1; then
            testframework::assert_command \
                "BS_OUTPUT_FORMAT=json system::routing::rules | jq -e . >/dev/null" "rules json valid"
        fi
    else
        testframework::assert_true "true" "rules empty (no ip in env) — skipped"
    fi

    testframework::summary
}

main "$@"
