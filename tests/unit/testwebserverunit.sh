#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testwebserverunit.sh — unit tests for lib/integration/webserver (parser, header, respond)
# tests/unit/testwebserverunit.sh — модульные тесты lib/integration/webserver (парсер, заголовок, ответ)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
load "lib/integration/webserver"

eq() { testframework::assert_equal "$@"; }

test_parse() {
    local out
    out="$(printf 'GET /path?a=1 HTTP/1.1\r\nHost: example.com\r\nX-Custom: hi\r\nContent-Length: 5\r\n\r\nhello' | {
        web::read_request
        printf '%s|%s|%s|%s' "${__web_method}" "${__web_path}" "${__web_version}" "${__web_body}"
    })"
    eq "GET|/path?a=1|HTTP/1.1|hello" "${out}" "request line and body"
}

test_header() {
    local out
    out="$(printf 'GET / HTTP/1.1\r\nUser-Agent: curl\r\n\r\n' | { web::read_request; web::header user-agent; })"
    eq "curl" "${out}" "header lookup is case-insensitive"
    out="$(printf 'GET / HTTP/1.1\r\n\r\n' | { web::read_request; web::header missing-header; })"
    eq "" "${out}" "missing header is empty"
}

test_respond() {
    eq $'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nhi' \
       "$(web::respond 200 OK "hi" "text/plain")" "response format"
    eq "1" "$(web::respond 404 'Not Found' '' 'text/plain' | grep -c '^Content-Length: 0')" "empty body Content-Length 0"
}

test_eof() {
    local rc=0
    web::read_request </dev/null || rc=$?
    eq "1" "${rc}" "EOF is a clean no-request"
}

test_respond_injection() {
    local rc=0 out
    out="$(web::respond 200 $'OK\r\nX-Injected: yes' "body" "text/plain" 2>/dev/null)" || rc=$?
    eq "2" "${rc}" "reason with CRLF is rejected"
    eq "" "${out}" "nothing is written on rejection"
}

test_body_limit() {
    local rc=0
    printf 'POST / HTTP/1.1\r\nContent-Length: 999999999\r\n\r\n' | { web::read_request; } >/dev/null 2>&1 || rc=$?
    eq "2" "${rc}" "oversized Content-Length is rejected"
    rc=0
    printf 'POST / HTTP/1.1\r\nContent-Length: 4\r\n\r\nabcd' | { web::read_request; } >/dev/null 2>&1 || rc=$?
    eq "0" "${rc}" "a small body is accepted"
}

main() {
    print_header "Webserver Unit Tests / Модульные тесты webserver"
    testframework::init
    testframework::section "Parse / Парсинг"; test_parse
    testframework::section "Header / Заголовок"; test_header
    testframework::section "Respond / Ответ"; test_respond
    testframework::section "EOF / Конец потока"; test_eof
    testframework::section "Safety / Безопасность"; test_respond_injection
    testframework::section "Body limit / Лимит тела"; test_body_limit
    testframework::summary
}

main "$@"
