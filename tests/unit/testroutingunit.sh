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

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
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

    testframework::section "mutators with a fake ip / изменяющие команды с подставным ip"
    local fake_bin rc
    fake_bin="$(mktemp -d)"
    cat > "${fake_bin}/ip" <<FAKE
#!/bin/sh
echo "\$*" >> "${fake_bin}/calls"
case "\$*" in
  *999.999*) echo "Error: inet address is expected" >&2; exit 2 ;;
esac
exit 0
FAKE
    chmod +x "${fake_bin}/ip"
    local old_path="${PATH}"
    PATH="${fake_bin}:${PATH}"
    rc=0; system::routing::default 999.999.0.1 >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -ne 0" "a failing default route is reported"
    testframework::assert_command "! grep -q 'route del default' '${fake_bin}/calls'" "the old default route is never deleted first"
    : > "${fake_bin}/calls"
    rc=0; system::routing::default 10.0.0.1 eth0 >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "default route set"
    testframework::assert_equal "route replace default via 10.0.0.1 dev eth0" "$(cat "${fake_bin}/calls")" "one atomic 'ip route replace'"
    : > "${fake_bin}/calls"
    local IFS=$'\n\t'
    rc=0; system::routing::policy "from 10.0.0.0/8 table 100" add >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "policy rule added"
    testframework::assert_equal "rule add from 10.0.0.0/8 table 100" "$(cat "${fake_bin}/calls")" "the rule is split into words even with IFS=newline"
    rc=0; system::routing::add 10.1.0.0/16 999.999.0.1 >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -ne 0" "a failing route add is reported"
    PATH="${old_path}"
    rm -rf "${fake_bin}"

    testframework::summary
}

main "$@"
