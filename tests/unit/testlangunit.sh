#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testlangunit.sh — Unit tests for core/lang module
# tests/unit/testlangunit.sh — Модульные тесты для модуля core/lang

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Test bs::func_name returns the caller's name
test_func_name() {
    test::sample_function() {
        bs::func_name
    }
    testframework::assert_equal "test::sample_function" "$(test::sample_function)" "bs::func_name detects caller"

    # Depth 2: name of the caller's caller
    # Глубина 2: имя вызывающего выше
    test::deep_inner() { bs::func_name 2; }
    test::deep_outer() { test::deep_inner; }
    testframework::assert_equal "test::deep_outer" "$(test::deep_outer)" "bs::func_name honors depth"
}

# Test bs::call_stack prints frames
test_call_stack() {
    test::inner() { bs::call_stack; }
    test::outer() { test::inner; }
    local stack
    stack="$(test::outer)"
    testframework::assert_true "'${stack}' == *'test::inner'*" "call_stack contains inner frame"
    testframework::assert_true "'${stack}' == *'test::outer'*" "call_stack contains outer frame"
}

# Test bs::is_function / bs::is_defined / bs::type_of
test_type_predicates() {
    testframework::assert_command "bs::is_function bs::guard" "is_function finds bs::guard"
    testframework::assert_false "bs::is_function not-a-real-function-xyz" "is_function rejects unknown name"

    local sample_var="x"
    testframework::assert_command "bs::is_defined sample_var" "is_defined finds variable"
    testframework::assert_false "bs::is_defined sample_undefined_xyz" "is_defined rejects unknown variable"

    local -a sample_arr=(one two)
    local -A sample_map=([k]=v)
    local -i sample_int=42
    testframework::assert_equal "function" "$(bs::type_of bs::guard)" "type_of detects function"
    testframework::assert_equal "string" "$(bs::type_of sample_var)" "type_of detects string"
    testframework::assert_equal "array" "$(bs::type_of sample_arr)" "type_of detects array"
    testframework::assert_equal "map" "$(bs::type_of sample_map)" "type_of detects map"
    testframework::assert_equal "integer" "$(bs::type_of sample_int)" "type_of detects integer"
    testframework::assert_equal "undefined" "$(bs::type_of sample_undefined_xyz)" "type_of detects undefined"
}

# Test str:: functions
test_strings() {
    testframework::assert_equal "HELLO" "$(str::upper "hello")" "str::upper"
    testframework::assert_equal "hello" "$(str::lower "HeLLo")" "str::lower"
    testframework::assert_equal "hello" "$(str::trim "   hello   ")" "str::trim both sides"
    testframework::assert_equal "" "$(str::trim '   ')" "str::trim all-whitespace"
    testframework::assert_equal "a-b-c" "$(str::replace "a b c" " " "-")" "str::replace all spaces"
    testframework::assert_command "str::contains 'hello world' 'lo wo'" "str::contains finds substring"
    testframework::assert_false "str::contains 'hello' 'xyz'" "str::contains rejects"
    testframework::assert_command "str::starts_with 'hello' 'he'" "str::starts_with yes"
    testframework::assert_false "str::starts_with 'hello' 'lo'" "str::starts_with no"
    testframework::assert_command "str::ends_with 'hello' 'lo'" "str::ends_with yes"
    testframework::assert_false "str::ends_with 'hello' 'he'" "str::ends_with no"
}

# Test arr:: functions
test_arrays() {
    local -a fruits=(apple banana)

    testframework::assert_equal "2" "$(arr::length fruits)" "arr::length"

    arr::push fruits cherry
    testframework::assert_equal "3" "$(arr::length fruits)" "arr::push grows array"
    testframework::assert_equal "cherry" "${fruits[2]}" "arr::push appends value"

    testframework::assert_command "arr::contains fruits banana" "arr::contains finds element"
    testframework::assert_false "arr::contains fruits kiwi" "arr::contains rejects missing"

    testframework::assert_equal "apple, banana, cherry" "$(arr::join fruits ', ')" "arr::join"
}

# Test map::has
test_maps() {
    local -A colors=([red]="#f00" [green]="#0f0")
    testframework::assert_command "map::has colors red" "map::has finds key"
    testframework::assert_false "map::has colors blue" "map::has rejects missing key"
}

main() {
    print_header "Core Lang Unit Tests / Модульные тесты core/lang"

    testframework::init

    testframework::section "Introspection / Интроспекция"
    test_func_name
    test_call_stack
    test_type_predicates

    testframework::section "Strings / Строки"
    test_strings

    testframework::section "Collections / Коллекции"
    test_arrays
    test_maps

    testframework::summary
}

main "$@"
