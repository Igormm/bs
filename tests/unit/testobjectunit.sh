#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testobjectunit.sh — core/object.sh through the loader: aliases, lifetime, subshell isolation
# tests/unit/testobjectunit.sh — core/object.sh через загрузчик: псевдонимы, время жизни, изоляция подоболочек

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
export BS_HOME="${BS_PROJECT_ROOT}"
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

load "core/object"

test_loaded_via_load() {
    testframework::assert_command 'declare -f bs_obj_new >/dev/null' "load core/object defines bs_obj_new"
    testframework::assert_command 'declare -f object::new >/dev/null' "the object::new alias exists in bash"
    testframework::assert_command 'declare -f object::equal >/dev/null' "the object::equal alias exists in bash"
    testframework::assert_command 'bs_load_is_loaded core/object' "the loader marks core/object as loaded"
}

test_lifecycle_in_bash() {
    local a b
    object::class TUCounter
    object::field TUCounter n 0
    object::method TUCounter inc tuc_inc
    object::new_to a TUCounter
    object::new_to b TUCounter n=5
    testframework::assert_equal "0" "$(object::get "$a" n)" "default field"
    testframework::assert_equal "5" "$(object::get "$b" n)" "pair initialization"
    object::call "$a" inc
    testframework::assert_equal "1" "$(object::get "$a" n)" "method mutates the current shell"
    testframework::assert_command "object::equal '$a' '$a'" "equal is reflexive"
    testframework::assert_command "! object::same '$a' '$b'" "distinct IDs are not identical"
    object::destroy "$a"
    object::destroy "$b"
    testframework::assert_equal "0" "$(object::count)" "destroy empties the registry"
}

tuc_inc() {
    local v
    v="$(object::get "$1" n)"
    object::set "$1" n "$((v + 1))"
}

test_subshell_isolation() {
    local before after lost
    object::class TUSub
    before="$(object::count)"
    lost="$(object::new TUSub)"
    after="$(object::count)"
    testframework::assert_equal "${before}" "${after}" "an object created in \$(...) stays in the subshell"
    testframework::assert_command "! object::alive '${lost}'" "the subshell ID is not live outside"
    object::destroy_all
}

test_strict_mode_safety() {
    local out rc=0
    out="$(bash -c '
        set -euo pipefail
        BS_ROOT="'"${BS_PROJECT_ROOT}"'"
        BS_CURRENT_FILE="${BS_ROOT}/bootstrap/shell.sh"; . "${BS_ROOT}/bootstrap/shell.sh"
        BS_CURRENT_FILE="${BS_ROOT}/core/prereq.sh"; . "${BS_ROOT}/core/prereq.sh"
        BS_CURRENT_FILE="${BS_ROOT}/core/data.sh"; . "${BS_ROOT}/core/data.sh"
        BS_CURRENT_FILE="${BS_ROOT}/core/object.sh"; . "${BS_ROOT}/core/object.sh"
        bs_obj_class Strict
        bs_obj_field Strict x 0
        bs_obj_new_to s Strict
        if bs_obj_get "$s" missing 2>/dev/null; then echo bad; else echo "rc=$?"; fi
        if bs_obj_set "$s" missing 1 2>/dev/null; then echo bad; else echo "rc=$?"; fi
        bs_obj_destroy_all
        echo alive
    ' 2>&1)" || rc=$?
    testframework::assert_equal "0" "${rc}" "a failing get/set does not kill a set -e script"
    testframework::assert_equal "rc=1
rc=1
alive" "${out}" "the failures are reported by status, the script lives on"
}

test_examples_run() {
    local out
    out="$("${BS_PROJECT_ROOT}/bs" "${BS_PROJECT_ROOT}/example_core/counter.sh" 2>&1)"
    testframework::assert_command "grep -q 'count=2 double=4' <<< '${out}'" "counter.sh demonstrates methods and properties"
    testframework::assert_command "grep -q 'after destroy_all: 0' <<< '${out}'" "counter.sh cleans up"
    out="$("${BS_PROJECT_ROOT}/bs" "${BS_PROJECT_ROOT}/example_core/shapes.sh" 2>&1)"
    testframework::assert_command "grep -q 'circle is_a shape: area=12' <<< '${out}'" "shapes.sh demonstrates inheritance"
    testframework::assert_command "grep -q 'window delegates area: 12' <<< '${out}'" "shapes.sh demonstrates delegation"
}

main() {
    testframework::section "Loaded via load / Загрузка через load"; test_loaded_via_load
    testframework::section "Lifecycle in bash / Время жизни в bash"; test_lifecycle_in_bash
    testframework::section "Subshell isolation / Изоляция подоболочек"; test_subshell_isolation
    testframework::section "Strict mode safety / Безопасность в set -e"; test_strict_mode_safety
    testframework::section "Examples run / Примеры запускаются"; test_examples_run
    testframework::summary
}

main "$@"
