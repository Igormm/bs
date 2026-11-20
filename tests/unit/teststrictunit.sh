#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/teststrictunit.sh — core/strict.sh through the kernel: auto-load, aliases, examples, doctor
# tests/unit/teststrictunit.sh — core/strict.sh через ядро: автозагрузка, псевдонимы, примеры, doctor

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
export BS_HOME="${BS_PROJECT_ROOT}"
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

test_auto_loaded() {
    testframework::assert_command 'declare -f bs_strict_enable >/dev/null' "the full kernel auto-loads core/strict.sh"
    testframework::assert_command 'declare -f strict::enable >/dev/null' "the strict::enable alias exists in bash"
    testframework::assert_command 'bs_load_is_loaded core/strict' "the loader marks core/strict as loaded"
    testframework::assert_command 'declare -f bs_strict >/dev/null' "the pre-kernel bs_strict still exists (base.sh)"
}

test_enable_in_bash() {
    local out
    out="$(bash -c '
        BS_ROOT="'"${BS_PROJECT_ROOT}"'"
        BS_CURRENT_FILE="${BS_ROOT}/bootstrap/shell.sh"; . "${BS_ROOT}/bootstrap/shell.sh"
        BS_CURRENT_FILE="${BS_ROOT}/bootstrap/kernel.sh"; . "${BS_ROOT}/bootstrap/kernel.sh"
        strict::enable
        strict::status
        marker() { printf "cleaned"; }
        bs_cleanup_add marker
    ' 2>&1)"
    testframework::assert_command "grep -q 'errexit=on' <<< '${out}'" "enable turns errexit on"
    testframework::assert_command "grep -q 'pipefail=on' <<< '${out}'" "bash has pipefail"
    testframework::assert_command "grep -q 'traps=EXIT ERR INT TERM HUP' <<< '${out}'" "all five traps are installed in bash"
    testframework::assert_command "grep -q 'cleaned' <<< '${out}'" "the EXIT cleanup ran at the end"
}

test_err_backtrace_and_code() {
    local out rc=0
    out="$(bash -c '
        BS_ROOT="'"${BS_PROJECT_ROOT}"'"
        BS_CURRENT_FILE="${BS_ROOT}/bootstrap/shell.sh"; . "${BS_ROOT}/bootstrap/shell.sh"
        BS_CURRENT_FILE="${BS_ROOT}/bootstrap/kernel.sh"; . "${BS_ROOT}/bootstrap/kernel.sh"
        strict::enable
        exit 7
    ' 2>&1)" || rc=$?
    testframework::assert_equal "7" "${rc}" "the failing code reaches the caller"
    out="$(bash -c '
        BS_ROOT="'"${BS_PROJECT_ROOT}"'"
        BS_CURRENT_FILE="${BS_ROOT}/bootstrap/shell.sh"; . "${BS_ROOT}/bootstrap/shell.sh"
        BS_CURRENT_FILE="${BS_ROOT}/bootstrap/kernel.sh"; . "${BS_ROOT}/bootstrap/kernel.sh"
        strict::enable
        false
    ' 2>&1)" || rc=$?
    testframework::assert_equal "1" "${rc}" "a failed command exits with its code"
    testframework::assert_command "grep -q 'Backtrace' <<< '${out}'" "the ERR trap prints a backtrace"
}

test_examples_use_the_abstraction() {
    local f
    for f in counter shapes cache_demo; do
        testframework::assert_command "grep -q 'strict::enable' '${BS_PROJECT_ROOT}/example_core/${f}.sh'" "example_core/${f}.sh uses strict::enable"
        testframework::assert_command "! grep -q '^set -euo pipefail' '${BS_PROJECT_ROOT}/example_core/${f}.sh'" "example_core/${f}.sh has no hand-written set -euo pipefail"
        testframework::assert_command "'${BS_PROJECT_ROOT}/bs' '${BS_PROJECT_ROOT}/example_core/${f}.sh' >/dev/null 2>&1" "example_core/${f}.sh runs"
    done
}

test_doctor_knows_the_file() {
    testframework::assert_command "BS_SILENT=0 '${BS_PROJECT_ROOT}/bs' doctor 2>&1 | grep 'core/strict.sh' >/dev/null" "bs doctor checks core/strict.sh"
}

main() {
    testframework::section "Auto-loaded / Автозагрузка"; test_auto_loaded
    testframework::section "Enable in bash / Включение в bash"; test_enable_in_bash
    testframework::section "ERR backtrace and code / ERR-трассировка и код"; test_err_backtrace_and_code
    testframework::section "Examples use the abstraction / Примеры на абстракции"; test_examples_use_the_abstraction
    testframework::section "Doctor / Doctor"; test_doctor_knows_the_file
    testframework::summary
}

main "$@"
