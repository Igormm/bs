#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testmtestunit.sh — runs the multi-shell core tests of mtest/ (bash, zsh, ash, dash, nushell)
# tests/unit/testmtestunit.sh — запускает мульти-оболочечные тесты ядра из mtest/ (bash, zsh, ash, dash, nushell)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

main() {
    local out rc=0
    testframework::section "mtest: S1-S4 of every core module / сценарии S1-S4 каждого модуля ядра"
    out="$(bash "${BS_PROJECT_ROOT}/mtest/run.sh" 2>&1)" || rc=$?
    testframework::assert_equal "0" "${rc}" "mtest/run.sh exits 0 (${out##*$'\n'})" || printf '%s\n' "${out}"
    testframework::summary
}

main "$@"
