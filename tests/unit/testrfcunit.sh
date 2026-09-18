#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testrfcunit.sh — Unit tests for lib/rfc modules
# tests/unit/testrfcunit.sh — Модульные тесты для модулей lib/rfc

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/rfc/uri"
load "lib/rfc/uuid"
load "lib/rfc/csv"

test_uri_parse() {
    uri::parse "https://user:pw@example.com:8080/a/b?x=1&y=2#frag"
    testframework::assert_equal "https" "${URI_SCHEME}" "uri scheme"
    testframework::assert_equal "user" "${URI_USER}" "uri user"
    testframework::assert_equal "pw" "${URI_PASSWORD}" "uri password"
    testframework::assert_equal "example.com" "${URI_HOST}" "uri host"
    testframework::assert_equal "8080" "${URI_PORT}" "uri port"
    testframework::assert_equal "/a/b" "${URI_PATH}" "uri path"
    testframework::assert_equal "x=1&y=2" "${URI_QUERY}" "uri query"
    testframework::assert_equal "frag" "${URI_FRAGMENT}" "uri fragment"

    uri::parse "ftp://files.example.com/pub"
    testframework::assert_equal "ftp" "${URI_SCHEME}" "uri scheme ftp"
    testframework::assert_equal "files.example.com" "${URI_HOST}" "uri host ftp"
    testframework::assert_equal "/pub" "${URI_PATH}" "uri path ftp"

    uri::parse "/just/a/path"
    testframework::assert_equal "" "${URI_SCHEME}" "uri no scheme"
    testframework::assert_equal "/just/a/path" "${URI_PATH}" "uri path only"

    uri::parse "mailto:user@example.com"
    testframework::assert_equal "mailto" "${URI_SCHEME}" "uri mailto scheme"
    testframework::assert_equal "user@example.com" "${URI_PATH}" "uri mailto path"

    # IPv6 / IPv6 в скобках
    uri::parse "http://[::1]:8080/x"
    testframework::assert_equal "::1" "${URI_HOST}" "uri ipv6 host"
    testframework::assert_equal "8080" "${URI_PORT}" "uri ipv6 port"

    # Кастомный префикс / Custom prefix
    uri::parse "https://h/p" U_
    testframework::assert_equal "h" "${U_HOST}" "uri custom prefix"
}

test_uri_decode_encode() {
    testframework::assert_equal "hello world!" "$(uri::decode "hello%20world%21")" "uri decode basic"
    testframework::assert_equal "a+b" "$(uri::decode "a%2Bb")" "uri decode plus stays"
    testframework::assert_equal "привет" "$(uri::decode "%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82")" "uri decode utf8"
    testframework::assert_equal "100%" "$(uri::decode "100%25")" "uri decode percent"

    testframework::assert_equal "a%20b%2Fc" "$(uri::encode "a b/c")" "uri encode basic"
    testframework::assert_equal "a.b~c" "$(uri::encode "a.b~c")" "uri encode unreserved"
    testframework::assert_equal "%D0%BF%D1%80" "$(uri::encode "пр")" "uri encode utf8 bytes"
}

test_uuid() {
    local u
    u="$(uuid::gen)"
    testframework::assert_equal "36" "${#u}" "uuid length"
    testframework::assert_command "uuid::validate '${u}'" "uuid::gen produces valid uuid"
    testframework::assert_command "uuid::validate '${u}' 4" "uuid::gen is version 4"
    testframework::assert_equal "4" "${u:14:1}" "uuid version nibble is 4"
    case "${u:19:1}" in
        8|9|a|b) testframework::assert_true "true" "uuid variant is 10xx" ;;
        *) testframework::assert_true "false" "uuid variant is 10xx" ;;
    esac

    local u7
    u7="$(uuid::gen_v7)"
    testframework::assert_command "uuid::validate '${u7}'" "uuid v7 valid"
    testframework::assert_equal "7" "${u7:14:1}" "uuid v7 version nibble"

    testframework::assert_false "uuid::validate 'not-a-uuid'" "uuid validate rejects garbage"
    testframework::assert_false "uuid::validate '12345678-1234-1234-1234-1234567890' 7" "uuid validate version mismatch"
}

test_csv() {
    local -a rows=() fields=()

    csv::rows "$(printf 'a,b\nc,d\n')" rows
    testframework::assert_equal "2" "${#rows[@]}" "csv rows count"
    testframework::assert_equal "c,d" "${rows[1]}" "csv rows content"

    # Кавычки, запятая внутри, экранированные кавычки, CRLF
    csv::fields 'a,"b,c","he said ""hi""",d' fields
    testframework::assert_equal "4" "${#fields[@]}" "csv fields count"
    testframework::assert_equal "a" "${fields[0]}" "csv field plain"
    testframework::assert_equal "b,c" "${fields[1]}" "csv field comma in quotes"
    testframework::assert_equal "he said \"hi\"" "${fields[2]}" "csv field escaped quotes"
    testframework::assert_equal "d" "${fields[3]}" "csv field last"

    # Пустые поля / Empty fields
    csv::fields "a,,c," fields
    testframework::assert_equal "4" "${#fields[@]}" "csv empty fields count"
    testframework::assert_equal "" "${fields[1]}" "csv empty field value"

    # Многострочное поле (RFC 4180 CRLF внутри кавычек)
    csv::rows "$(printf 'x,"multi\nline",y\n')" rows
    testframework::assert_equal "1" "${#rows[@]}" "csv multiline record count"
    csv::fields "${rows[0]}" fields
    testframework::assert_equal "multi
line" "${fields[1]}" "csv multiline field"

    # CRLF окончания строк / CRLF line endings
    csv::rows "$(printf 'a,b\r\nc,d\r\n')" rows
    testframework::assert_equal "2" "${#rows[@]}" "csv crlf rows"
    testframework::assert_equal "b" "$(csv::fields "${rows[0]}" fields; printf '%s' "${fields[1]}")" "csv crlf field clean"
}

test_rfc1925() {
    load "lib/rfc/rfc1925"
    testframework::assert_command "rfc1925::truths | grep -q 'It Has To Work'" "rfc1925 first truth"
    testframework::assert_command "rfc1925::truths | grep -q 'nothing left to take away'" "rfc1925 last truth"
}

main() {
    print_header "RFC Unit Tests / Модульные тесты RFC"

    testframework::init

    testframework::section "RFC 3986 URI"
    test_uri_parse
    test_uri_decode_encode

    testframework::section "RFC 4122/9562 UUID"
    test_uuid

    testframework::section "RFC 4180 CSV"
    test_csv

    testframework::section "RFC 1925"
    test_rfc1925

    testframework::summary
}

main "$@"