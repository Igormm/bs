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

# Test arr::from_lines reads stdin into an array
test_from_lines() {
    local -a lines=()
    arr::from_lines lines <<'EOF'
first
second
third
EOF
    testframework::assert_equal "3" "${#lines[@]}" "from_lines reads heredoc"
    testframework::assert_equal "second" "${lines[1]}" "from_lines preserves order"

    local -a pids=()
    arr::from_lines pids < <(printf 'a\nb\n')
    testframework::assert_equal "2" "${#pids[@]}" "from_lines works with process substitution"
}

# Test is:: predicate family
test_is_predicates() {
    testframework::assert_command "is::empty ''" "is::empty on empty string"
    testframework::assert_false "is::empty 'x'" "is::empty on non-empty"
    testframework::assert_command "is::not_empty 'x'" "is::not_empty on non-empty"
    testframework::assert_false "is::not_empty ''" "is::not_empty on empty"

    local tmp_file
    tmp_file="$(mktemp)"
    testframework::assert_command "is::exists '${tmp_file}'" "is::exists finds file"
    testframework::assert_command "is::file '${tmp_file}'" "is::file on regular file"
    testframework::assert_false "is::dir '${tmp_file}'" "is::dir rejects file"
    testframework::assert_command "is::readable '${tmp_file}'" "is::readable"
    testframework::assert_false "is::file_not_empty '${tmp_file}'" "is::file_not_empty on empty file"

    printf 'data' > "${tmp_file}"
    testframework::assert_command "is::file_not_empty '${tmp_file}'" "is::file_not_empty on filled file"

    local tmp_link="${tmp_file}.link"
    ln -s "${tmp_file}" "${tmp_link}"
    testframework::assert_command "is::symlink '${tmp_link}'" "is::symlink finds link"

    testframework::assert_command "is::dir /tmp" "is::dir on directory"
    testframework::assert_command "is::executable /bin/sh" "is::executable on /bin/sh"
    testframework::assert_false "is::exists '/definitely/not/here'" "is::exists rejects missing path"

    testframework::assert_command "is::number 42" "is::number on digits"
    testframework::assert_false "is::number '4x'" "is::number rejects mixed"

    testframework::assert_command "is::command bash" "is::command finds bash"
    testframework::assert_false "is::command not-a-real-cmd-xyz" "is::command rejects unknown"

    testframework::assert_command "is::function bs::guard" "is::function finds bs::guard"

    rm -f "${tmp_file}" "${tmp_link}"
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
    test_from_lines

    testframework::section "is:: predicates / Предикаты is::"
    test_is_predicates

    testframework::summary
}

main "$@"
