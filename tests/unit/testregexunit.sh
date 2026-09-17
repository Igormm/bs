#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testregexunit.sh — Unit tests for lib/data/regex module
# tests/unit/testregexunit.sh — Модульные тесты для модуля lib/data/regex

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/data/regex"

test_matches() {
    testframework::assert_command "regex::matches 'https://x.dev' '^https?://'" "regex::matches ERE anchor"
    testframework::assert_false "regex::matches 'ftp://x' '^https?://'" "regex::matches rejects non-match"
    testframework::assert_command "regex::matches 'log 2026-09-17 start' '[0-9]{4}-[0-9]{2}-[0-9]{2}'" "regex::matches ERE class"
    testframework::assert_command "regex::matches 'id: 42' '[0-9]+'" "regex::matches anywhere"

    if is::command grep; then
        testframework::assert_command "regex::matches 'date 2026-09-17' '\d{4}-\d{2}-\d{2}' --pcre" "regex::matches PCRE \d"
        testframework::assert_command "regex::matches 'foo123bar' 'foo(?=\d)' --pcre" "regex::matches PCRE lookahead"
        testframework::assert_false "regex::matches 'fooXbar' 'foo(?=\d)' --pcre" "regex::matches PCRE lookahead rejects"
        testframework::assert_command "regex::matches 'abab' '(ab)\1' --pcre" "regex::matches PCRE backref"
        testframework::assert_false "regex::matches 'abXab' '(ab)\1' --pcre" "regex::matches PCRE backref requires adjacency"
    fi
}

test_find() {
    local -a out=()
    regex::find "a1 b22 c333" '[0-9]+' out
    testframework::assert_equal "1 22 333" "$(arr::join out ' ')" "regex::find ERE all matches"
    regex::find "no digits" '[0-9]+' out
    testframework::assert_equal "0" "${#out[@]}" "regex::find zero matches is empty"

    if is::command grep; then
        regex::find "ids: 12-345 6-7890" '\d{2}-\d{3}' out --pcre
        testframework::assert_equal "12-345" "${out[0]}" "regex::find PCRE match"
    fi

    testframework::assert_equal "1
22
333" "$(regex::find "a1 b22 c333" '[0-9]+' '')" "regex::find stdout mode"
}

test_count() {
    testframework::assert_equal "2" "$(regex::count "x,y;z" '[,;]')" "regex::count ERE"
    testframework::assert_equal "0" "$(regex::count "abc" '[0-9]+')" "regex::count zero"
    if is::command grep; then
        testframework::assert_equal "2" "$(regex::count "a1b2" "\d" --pcre)" "regex::count PCRE"
    fi
}

test_groups() {
    local -a g=()
    regex::groups "v1.23" 'v([0-9]+)\.([0-9]+)' g
    testframework::assert_equal "2" "${#g[@]}" "regex::groups count"
    testframework::assert_equal "1" "${g[0]}" "regex::groups first group"
    testframework::assert_equal "23" "${g[1]}" "regex::groups second group"
    testframework::assert_false "regex::groups 'no match' 'v([0-9]+)' g" "regex::groups rejects no match"

    testframework::assert_equal "23" "$(regex::group "v1.23" 'v([0-9]+)\.([0-9]+)' 2)" "regex::group by index"
    testframework::assert_equal "v1.23" "$(regex::group "v1.23" 'v[0-9.]+')" "regex::group 0 default is whole match"
    testframework::assert_equal "log" "$(regex::group "app.log" '\.([^.]+)$' 1)" "regex::group extension"
    testframework::assert_false "regex::group 'x' '([0-9])' 5" "regex::group out of range"
}

test_replace() {
    testframework::assert_equal "a,b,c" "$(regex::replace "a;b;c" ';' ',')" "regex::replace literal"
    testframework::assert_equal "abc" "$(regex::replace "a1b2c3" '[0-9]+' '')" "regex::replace class"
    testframework::assert_equal "X and X" "$(regex::replace "user1 and user2" 'user[0-9]+' 'X')" "regex::replace multiple"
    testframework::assert_equal "a_Bc" "$(regex::replace "aBc" '([a-z])([A-Z])' '\1_\2')" "regex::replace backrefs"
    testframework::assert_equal "Doe John" "$(regex::replace "John Doe" '^(\w+) (\w+)$' '\2 \1')" "regex::replace swaps groups"
    testframework::assert_equal "x-y-z" "$(regex::replace "x/y/z" '/' '-')" "regex::replace slash in pattern"
    testframework::assert_equal "line1 line2" "$(regex::replace $'line1\nline2' $'\n' ' ')" "regex::replace newline (sed -z)"
}

test_split() {
    local -a s=()
    regex::split "a,1;b,2" '[,;]' s
    testframework::assert_equal "4" "${#s[@]}" "regex::split count"
    testframework::assert_equal "a 1 b 2" "$(arr::join s ' ')" "regex::split pieces"
    regex::split "no delimiters" '[0-9]+' s
    testframework::assert_equal "no delimiters" "${s[0]}" "regex::split no match keeps whole"
    regex::split "" '[0-9]+' s
    testframework::assert_equal "0" "${#s[@]}" "regex::split empty string"
}

main() {
    print_header "Regex Unit Tests / Модульные тесты regex"

    testframework::init

    testframework::section "matches / совпадение"
    test_matches

    testframework::section "find / поиск"
    test_find

    testframework::section "count / счёт"
    test_count

    testframework::section "groups / группы"
    test_groups

    testframework::section "replace / замена"
    test_replace

    testframework::section "split / разбиение"
    test_split

    testframework::summary
}

main "$@"