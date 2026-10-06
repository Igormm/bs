#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsshdunit.sh — Unit tests for lib/system/sshd
# tests/unit/testsshdunit.sh — Модульные тесты для lib/system/sshd

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/system/sshd"

main() {
    print_header "SSHd Unit Tests / Модульные тесты sshd"
    testframework::init

    testframework::section "catalog shape / форма каталога"
    local name meta fields
    for name in "${SSHD_PARAM_ORDER[@]}"; do
        meta="${SSHD_PARAMS[$name]:-}"
        testframework::assert_true "-n '${meta}'" "meta present: ${name}"
        fields="$(awk -F'|' '{print NF}' <<< "${meta}")"
        testframework::assert_equal "4" "${fields}" "4 fields: ${name}"
        testframework::assert_true "-n '${SSHD_TIPS[$name]:-}'" "tip present: ${name}"
        testframework::assert_command "LC_ALL=C grep -q '[^ -~]' <<< \"\${SSHD_TIPS[${name}]}\"" "tip non-ascii/cyrillic: ${name}"
    done

    testframework::section "param_list / список параметров"
    local count filtered
    count="$(sshd::param_list | wc -l)"
    testframework::assert_equal "${#SSHD_PARAM_ORDER[@]}" "${count}" "all params listed"
    filtered="$(sshd::param_list Network)"
    testframework::assert_true "-n '${filtered}'" "Network filter non-empty"
    testframework::assert_command "! printf '%s' '${filtered}' | grep -q 'Authentication'" "Network filter excludes others"

    testframework::section "param_type / param_desc"
    testframework::assert_equal "bool" "$(sshd::param_type PasswordAuthentication)" "bool type"
    testframework::assert_equal "port" "$(sshd::param_type Port)" "port type"
    local desc
    desc="$(sshd::param_desc PasswordAuthentication)"
    testframework::assert_equal "2" "$(printf '%s\n' "${desc}" | wc -l)" "desc is two lines"
    local rc=0; sshd::param_type no_such_param >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "unknown param → invalid args"

    testframework::section "param_default / param_recommended"
    testframework::assert_equal "22" "$(sshd::param_default Port)" "Port default 22"
    testframework::assert_equal "no" "$(sshd::param_recommended PasswordAuthentication)" "pw recommended no"

    testframework::summary
}

main "$@"
