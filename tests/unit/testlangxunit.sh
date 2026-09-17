#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testlangxunit.sh — Unit tests for lib/data/langx + str::format
# tests/unit/testlangxunit.sh — Модульные тесты для lib/data/langx + str::format

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/data/langx"

test_contracts() {
    # bs::pre passes on truth, fails on falsity
    local port="8080"
    bs::pre 'is::number "$port"' "port must be numeric"
    testframework::assert_command "port=8080; bs::pre 'is::number \"\$port\"'" "bs::pre passes on valid condition"
    testframework::assert_false "port=abc; bs::pre 'is::number \"\$port\"'" "bs::pre fails on invalid condition"
    testframework::assert_false "bs::pre 'false'" "bs::pre rejects false"
    testframework::assert_command "bs::pre 'true'" "bs::pre accepts true"

    # bs::post
    local result="ok"
    testframework::assert_command "result=ok; bs::post 'is::not_empty \"\$result\"'" "bs::post passes"
    testframework::assert_false "result=''; bs::post 'is::not_empty \"\$result\"'" "bs::post fails on empty result"

    # error message mentions the message
    testframework::assert_command "( port=abc; bs::pre 'is::number \"\$port\"' 'port must be numeric' 2>&1 || true ) | grep -q 'port must be numeric'" "bs::pre prints the message"
}

test_capture() {
    local out=""
    bs::capture out printf 'hello %s' world
    testframework::assert_equal "hello world" "${out}" "bs::capture stores stdout"
    testframework::assert_equal "0" "$?" "bs::capture keeps success code"

    bs::capture out sh -c 'echo boom; exit 3' || local rc=$?
    testframework::assert_equal "3" "${rc}" "bs::capture keeps failure code"
    testframework::assert_equal "boom" "${out}" "bs::capture stores output of failing command"

    local json
    json="$(bs::capture_json printf 'x=%s' 42)"
    testframework::assert_equal "0" "$(printf '%s' "${json}" | jq '.code')" "bs::capture_json code"
    testframework::assert_equal "x=42" "$(printf '%s' "${json}" | jq -r '.stdout')" "bs::capture_json stdout"
}

test_parallel() {
    test_par_a() { sleep 0.1; echo "A"; }
    test_par_b() { echo "B"; }
    test_par_bad() { echo "bad"; return 7; }

    local out
    out="$(bs::parallel test_par_a test_par_b)" || true
    testframework::assert_command "printf '%s' '${out}' | grep -q '=== test_par_a ==='" "bs::parallel prints section header"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^A$'" "bs::parallel captures first output"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^B$'" "bs::parallel captures second output"

    testframework::assert_false "bs::parallel test_par_bad" "bs::parallel reports failure"
    testframework::assert_false "bs::parallel not_a_fn_xyz" "bs::parallel rejects missing function"
}

test_reflect() {
    # compgen sees functions defined in this session
    test_reflect::my_fn() { :; }
    # grep without -q: full consumption — -q closes the pipe early and
    # the writer hits EPIPE (fails under pipefail)
    testframework::assert_command "bs::reflect 'test_reflect::*' | grep 'test_reflect::my_fn' >/dev/null" "bs::reflect finds by pattern"
    testframework::assert_command "bs::reflect 'bs::*' | grep 'bs::type_of' >/dev/null" "bs::reflect finds framework functions"
    testframework::assert_false "bs::reflect 'zzz::*' | grep . >/dev/null" "bs::reflect empty for unknown namespace"
}

test_num() {
    testframework::assert_equal "10" "$(bs::num '0b1010')" "bs::num binary"
    testframework::assert_equal "255" "$(bs::num '0xFF')" "bs::num hex"
    testframework::assert_equal "17" "$(bs::num '021')" "bs::num octal"
    testframework::assert_equal "1000000" "$(bs::num '1_000_000')" "bs::num underscore separator"
    testframework::assert_equal "1234567" "$(bs::num "1'234'567")" "bs::num quote separator"
    testframework::assert_equal "-10" "$(bs::num '-0b1010')" "bs::num negative binary"
    testframework::assert_equal "0" "$(bs::num '0')" "bs::num zero"
    testframework::assert_false "bs::num '0b102'" "bs::num rejects invalid digits"
    testframework::assert_false "bs::num 'abc'" "bs::num rejects garbage"
    testframework::assert_false "bs::num ''" "bs::num rejects empty"
    testframework::assert_equal "1" "$(bs::num '1_')" "bs::num strips trailing separator"

    testframework::assert_command "is::int '0b1010'" "is::int binary"
    testframework::assert_false "is::int '0b102'" "is::int rejects bad binary"
}

test_str_format() {
    testframework::assert_equal "hello world, attempt 42" "$(str::format "hello {name}, attempt {1}" name=world 42)" "str::format named + positional"
    testframework::assert_equal "a,b,c" "$(str::format "{1},{2},{3}" a b c)" "str::format positional only"
    testframework::assert_equal "x" "$(str::format "x")" "str::format no placeholders"
    testframework::assert_equal "value with spaces" "$(str::format "value {k}" "k=with spaces")" "str::format value with spaces"
    testframework::assert_equal "left {unset} right" "$(str::format "left {unset} right" name=x)" "str::format leaves unknown placeholders"
}

test_go_features() {
    # is::float (Go strconv.ParseFloat)
    testframework::assert_command "is::float '3.14'" "is::float decimal"
    testframework::assert_command "is::float '.5'" "is::float leading dot"
    testframework::assert_command "is::float '2.'" "is::float trailing dot"
    testframework::assert_command "is::float '1e-3'" "is::float exponent"
    testframework::assert_command "is::float '-0.5'" "is::float negative"
    testframework::assert_false "is::float 'abc'" "is::float rejects garbage"
    testframework::assert_false "is::float '1.2.3'" "is::float rejects double dot"

    # bs::enum (Go iota)
    bs::enum ERR_OK ERR_TIMEOUT ERR_BUSY
    testframework::assert_equal "1" "${ERR_OK}" "bs::enum first = 1"
    testframework::assert_equal "3" "${ERR_BUSY}" "bs::enum third = 3"
    bs::enum 10 TEN TWENTY
    testframework::assert_equal "10" "${TEN}" "bs::enum custom start"
    testframework::assert_equal "11" "${TWENTY}" "bs::enum increments from start"
    testframework::assert_false "bs::enum 'bad name'" "bs::enum rejects invalid name"

    # bs::rand (Go math/rand)
    local r
    r="$(bs::rand 5 5)"
    testframework::assert_equal "5" "${r}" "bs::rand fixed range"
    r="$(bs::rand 10 20)"
    testframework::assert_command "(( r >= 10 && r <= 20 ))" "bs::rand stays in range"
    testframework::assert_false "bs::rand 20 10" "bs::rand rejects inverted range"

    # bs::embed (Go embed)
    local tmp_file
    tmp_file="$(mktemp)"
    printf 'line one\ntwo'\''quoted\n' > "${tmp_file}"
    local data=""
    eval "data=$(bs::embed "${tmp_file}")"
    testframework::assert_equal "line one
two'quoted" "${data}" "bs::embed round-trips content"
    testframework::assert_false "bs::embed /definitely/not/here" "bs::embed rejects missing file"
    rm -f "${tmp_file}"
}

main() {
    print_header "Langx Unit Tests / Модульные тесты langx"

    testframework::init

    testframework::section "Contracts / Контракты"
    test_contracts

    testframework::section "Capture / Захват"
    test_capture

    testframework::section "Parallel / Параллельность"
    test_parallel

    testframework::section "Reflect / Рефлексия"
    test_reflect

    testframework::section "Numbers / Числа"
    test_num

    testframework::section "Format / Форматирование"
    test_str_format

    testframework::section "Go features / Go-фичи"
    test_go_features

    testframework::summary
}

main "$@"