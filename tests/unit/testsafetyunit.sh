#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsafetyunit.sh — Unit tests for lib/system/safety.sh
# tests/unit/testsafetyunit.sh — Модульные тесты для lib/system/safety.sh
#
# Only pure checks: nothing is changed on the system.
# Только чистые проверки: система не изменяется.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
load "lib/system/safety"

# The reason is read from the message: as root a system directory is also
# writable, so the exit code alone does not tell "dangerous" from "not writable"
# Причина читается из сообщения: у root системный каталог тоже доступен на
# запись, и код возврата сам не отличает «опасный» от «недоступный»
test_validate_path_dangerous() {
    local p out
    for p in / // /etc /etc/ /etc/. /usr// /tmp/../etc; do
        out="$(safety::validate_path "${p}" 2>&1 || true)"
        testframework::assert_true "'${out}' == *Dangerous* " "system directory '${p}' is rejected as dangerous"
    done
}

test_validate_path_empty() {
    local rc=0
    safety::validate_path "" >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -ne 0" "an empty path is rejected"
}

test_validate_path_ok() {
    local tmp
    tmp="$(mktemp -d)"
    testframework::assert_command "safety::validate_path '${tmp}/new file'" "a path in a temp dir is accepted"
    rm -rf "${tmp}"
}

test_needs_confirmation() {
    SAFETY_DRY_RUN=false
    SAFETY_LEVEL=normal
    testframework::assert_command "safety::needs_confirmation critical" "normal: critical needs confirmation"
    testframework::assert_false "safety::needs_confirmation high" "normal: high does not"
    SAFETY_LEVEL=strict
    testframework::assert_command "safety::needs_confirmation high" "strict: high needs confirmation"
    testframework::assert_false "safety::needs_confirmation medium" "strict: medium does not"
    SAFETY_LEVEL=relaxed
    testframework::assert_false "safety::needs_confirmation critical" "relaxed: nothing needs confirmation"
    SAFETY_LEVEL=normal
}

test_execute_dry_run() {
    local tmp
    tmp="$(mktemp -d)"
    safety::dry_run true >/dev/null 2>&1
    safety::execute low "touch" touch "${tmp}/f" >/dev/null 2>&1
    safety::dry_run false >/dev/null 2>&1
    testframework::assert_command "test ! -e '${tmp}/f'" "dry-run does not run the command"
    safety::execute low "touch" touch "${tmp}/f" >/dev/null 2>&1
    testframework::assert_command "test -e '${tmp}/f'" "without dry-run the command runs"
    rm -rf "${tmp}"
}

main() {
    print_header "Safety Unit Tests / Модульные тесты safety"

    testframework::init

    testframework::section "validate_path"
    test_validate_path_dangerous
    test_validate_path_empty
    test_validate_path_ok

    testframework::section "confirmation and dry-run"
    test_needs_confirmation
    test_execute_dry_run

    testframework::summary
}

main "$@"
