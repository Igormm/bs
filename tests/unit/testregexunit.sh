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

test_pcre_probe_cache() {
    # проба выполняется один раз и кэшируется в RX_PCRE / probe runs once, cached
    RX_PCRE=""
    regex::matches 'x' 'x' --pcre >/dev/null || true
    testframework::assert_true '${RX_PCRE} == "1" || ${RX_PCRE} == "0"' "RX_PCRE probed and cached"

    if is::command perl; then
        # эмуляция BSD: grep -P недоступен → фолбэк на perl / BSD emulation: perl fallback
        RX_PCRE=0
        testframework::assert_command "regex::matches 'date 2026-09-17' '\d{4}-\d{2}-\d{2}' --pcre" "PCRE fallback to perl matches"
        RX_PCRE=0
        testframework::assert_false "regex::matches 'no date' '\d{4}-\d{2}-\d{2}' --pcre" "PCRE fallback to perl rejects"
        RX_PCRE=0
        testframework::assert_false "regex::matches 'fooXbar' 'foo(?=\d)' --pcre" "PCRE fallback to perl lookahead"

        local -a out=()
        RX_PCRE=0
        regex::find "ids: 12-345 67-890" '\d{2}-\d{3}' out --pcre
        testframework::assert_equal "12-345 67-890" "$(arr::join out ' ')" "PCRE fallback to perl find"
        RX_PCRE=0
        testframework::assert_equal "2" "$(regex::count "a1b2" '\d' --pcre)" "PCRE fallback to perl count"
    fi

    # движок отсутствует полностью → явный код ошибки (не 2, не 1) /
    # engine missing entirely → distinct error code (not 2, not 1)
    local mock_dir
    mock_dir="$(mktemp -d)"
    ln -s "$(command -v grep)" "${mock_dir}/grep"
    local old_path="${PATH}"
    PATH="${mock_dir}"
    RX_PCRE=0
    local rc=0
    if regex::matches 'x' 'x' --pcre 2>/dev/null; then
        rc=0
    else
        rc=$?
    fi
    PATH="${old_path}"
    rm -rf "${mock_dir}"
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING:-101}" "${rc}" "PCRE unavailable returns distinct error code"
    # shellcheck disable=SC2034
    RX_PCRE=""
}

test_replace_fallback() {
    # фолбэк возвращает данные (не пусто) / fallback returns data (not empty)
    RX_SED_Z=0
    testframework::assert_equal "aXbXcX" "$(regex::replace "a1b2c3" '[0-9]+' 'X')" "sed -z fallback returns data (perl/bash)"

    # кэш пробы устанавливается первым вызовом / probe cache set on first call
    RX_SED_Z=""
    regex::replace "a1b2c3" '[0-9]+' 'X' >/dev/null
    testframework::assert_true '${RX_SED_Z} == "1" || ${RX_SED_Z} == "0"' "RX_SED_Z probed and cached"

    # обратные ссылки работают в фолбэке / backrefs work in fallback
    RX_SED_Z=0
    testframework::assert_equal "a_Bc" "$(regex::replace "aBc" '([a-z])([A-Z])' '\1_\2')" "fallback backrefs"
    RX_SED_Z=0
    testframework::assert_equal "Doe John" "$(regex::replace "John Doe" '^(\w+) (\w+)$' '\2 \1')" "fallback swaps groups"

    # сбой движка не маскируется пустым результатом / engine failure is not masked
    local rc=0
    RX_SED_Z=1
    if regex::replace "abc" '[' 'x' >/dev/null 2>&1; then
        rc=0
    else
        rc=$?
    fi
    testframework::assert_true "${rc} -ne 0" "sed failure propagates non-zero status"

    if is::command perl; then
        RX_SED_Z=0
        if regex::replace "abc" '[' 'x' >/dev/null 2>&1; then
            rc=0
        else
            rc=$?
        fi
        testframework::assert_true "${rc} -ne 0" "perl fallback failure propagates non-zero status"
    fi
    # shellcheck disable=SC2034
    RX_SED_Z=""
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

    testframework::section "replace fallback / фолбэк replace"
    test_replace_fallback

    testframework::section "pcre probe and fallback / проба и фолбэк PCRE"
    test_pcre_probe_cache

    testframework::section "split / разбиение"
    test_split

    testframework::summary
}

main "$@"