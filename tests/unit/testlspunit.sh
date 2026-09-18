#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testlspunit.sh — Unit tests for lib/data/lsp module
# tests/unit/testlspunit.sh — Модульные тесты для модуля lib/data/lsp

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/data/langdoc"
load "lib/data/lsp"

# Frame a JSON-RPC message with Content-Length headers / Обрамить сообщение
lsp_test::frame() {
    local -r msg="$1"
    local len
    len="$(printf '%s' "${msg}" | LC_ALL=C wc -c)"
    printf 'Content-Length: %s\r\n\r\n%s' "${len}" "${msg}"
}

# Extract response bodies from the server's output stream.
# Наши ответы однострочные (jq -c), но следующий заголовок приклеен
# сразу после тела — читаем ровно N байт, как настоящий LSP-клиент.
lsp_test::bodies() {
    local hdr blank body len
    while IFS= read -r hdr; do
        hdr="${hdr%$'\r'}"
        [[ "${hdr}" == Content-Length:* ]] || continue
        len="${hdr#Content-Length:}"
        len="${len// /}"
        IFS= read -r blank || return 0
        LC_ALL=C IFS= read -r -N "${len}" body || return 0
        printf '%s\n' "${body}"
    done
}

test_lsp_session() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local out
    out="$(
        {
            lsp_test::frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
            lsp_test::frame '{"jsonrpc":"2.0","method":"initialized","params":{}}'
            lsp_test::frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/demo.sh","languageId":"shell","version":1,"text":"arr::slice items out 1 4\n"}}}'
            lsp_test::frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///tmp/demo.sh"},"position":{"line":0,"character":4}}}'
            lsp_test::frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/demo.sh"},"position":{"line":0,"character":3}}}'
            lsp_test::frame '{"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///tmp/demo.sh"},"position":{"line":0,"character":12}}}'
            lsp_test::frame '{"jsonrpc":"2.0","id":5,"method":"unknown/method","params":{}}'
            lsp_test::frame '{"jsonrpc":"2.0","id":6,"method":"shutdown","params":null}'
            lsp_test::frame '{"jsonrpc":"2.0","method":"exit","params":null}'
        } | lsp::server 2>&1
    )" || true

    local -a resps=()
    local b
    while IFS= read -r b; do
        resps+=("${b}")
    done < <(printf '%s' "${out}" | lsp_test::bodies)

    testframework::assert_equal "6" "${#resps[@]}" "lsp responds to 6 requests"

    local i
    for i in "${!resps[@]}"; do
        printf '%s\n' "${resps[$i]}" > "${tmp_dir}/resp${i}.json"
    done

    # initialize / инициализация
    testframework::assert_equal "1" "$(jq -r '.id' "${tmp_dir}/resp0.json")" "lsp initialize echoes id"
    testframework::assert_equal "true" "$(jq -r '.result.capabilities.hoverProvider' "${tmp_dir}/resp0.json")" "lsp advertises hover"
    testframework::assert_equal "1" "$(jq -r '.result.capabilities.textDocumentSync' "${tmp_dir}/resp0.json")" "lsp advertises full sync"
    testframework::assert_command "jq -e '.result.capabilities.completionProvider.triggerCharacters | index(\":\")' '${tmp_dir}/resp0.json'" "lsp advertises completion trigger"

    # hover / наведение
    testframework::assert_equal "2" "$(jq -r '.id' "${tmp_dir}/resp1.json")" "lsp hover echoes id"
    testframework::assert_command "jq -e '.result.contents.value | contains(\"arr::slice\")' '${tmp_dir}/resp1.json'" "lsp hover finds arr::slice"
    testframework::assert_command "jq -e '.result.contents.value | contains(\"core/lang.sh\")' '${tmp_dir}/resp1.json'" "lsp hover shows source file"

    # completion / автодополнение
    testframework::assert_equal "3" "$(jq -r '.id' "${tmp_dir}/resp2.json")" "lsp completion echoes id"
    testframework::assert_equal "false" "$(jq -r '.result.isIncomplete' "${tmp_dir}/resp2.json")" "lsp completion is complete"
    testframework::assert_command "jq -e '.result.items | length > 0' '${tmp_dir}/resp2.json'" "lsp completion returns items"
    testframework::assert_command "jq -e '[.result.items[].label] | any(startswith(\"arr::\"))' '${tmp_dir}/resp2.json'" "lsp completion matches arr:: prefix"
    testframework::assert_command "jq -e '[.result.items[] | select(.label == \"arr::slice\")][0].documentation.value | contains(\"Слайс\")' '${tmp_dir}/resp2.json'" "lsp completion carries documentation"

    # hover на несуществующее слово → null
    testframework::assert_equal "null" "$(jq -c '.result' "${tmp_dir}/resp3.json")" "lsp hover unknown word is null"

    # неизвестный метод → null
    testframework::assert_equal "null" "$(jq -c '.result' "${tmp_dir}/resp4.json")" "lsp unknown method responds null"

    # shutdown → null
    testframework::assert_equal "null" "$(jq -c '.result' "${tmp_dir}/resp5.json")" "lsp shutdown responds null"

    rm -rf "${tmp_dir}"
}

test_lsp_open_file_functions() {
    # Functions defined in the OPEN document are indexed via the buffer.
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local out
    out="$(
        {
            lsp_test::frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
            lsp_test::frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/own.sh","languageId":"shell","version":1,"text":"# @description My own function / Моя функция\n# @param $1 First / Первый\nmy_own_fn() { :; }\nmy_own_fn x\n"}}}'
            lsp_test::frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///tmp/own.sh"},"position":{"line":3,"character":4}}}'
            lsp_test::frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/own.sh"},"position":{"line":3,"character":4}}}'
            lsp_test::frame '{"jsonrpc":"2.0","id":4,"method":"shutdown","params":null}'
            lsp_test::frame '{"jsonrpc":"2.0","method":"exit","params":null}'
        } | lsp::server 2>&1
    )" || true

    local -a resps=()
    local b
    while IFS= read -r b; do
        resps+=("${b}")
    done < <(printf '%s' "${out}" | lsp_test::bodies)

    local i
    for i in "${!resps[@]}"; do
        printf '%s\n' "${resps[$i]}" > "${tmp_dir}/r${i}.json"
    done

    testframework::assert_command "jq -e '.result.contents.value | contains(\"my_own_fn\")' '${tmp_dir}/r1.json'" "lsp hover finds open-file function"
    testframework::assert_command "jq -e '.result.contents.value | contains(\"Моя функция\")' '${tmp_dir}/r1.json'" "lsp hover shows open-file doc"
    testframework::assert_command "jq -e '[.result.items[].label] | any(. == \"my_own_fn\")' '${tmp_dir}/r2.json'" "lsp completion includes open-file function"

    rm -rf "${tmp_dir}"
}

test_lsp_did_change() {
    # Full sync: after didChange the buffer content is replaced.
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local out
    out="$(
        {
            lsp_test::frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
            lsp_test::frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/c.sh","languageId":"shell","version":1,"text":"old content\n"}}}'
            lsp_test::frame '{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///tmp/c.sh"},"contentChanges":[{"text":"str::slice \"hello\" 1 4\n"}]}}'
            lsp_test::frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///tmp/c.sh"},"position":{"line":0,"character":4}}}'
            lsp_test::frame '{"jsonrpc":"2.0","id":3,"method":"shutdown","params":null}'
            lsp_test::frame '{"jsonrpc":"2.0","method":"exit","params":null}'
        } | lsp::server 2>/dev/null
    )" || true

    local -a resps=()
    local b
    while IFS= read -r b; do
        resps+=("${b}")
    done < <(printf '%s' "${out}" | lsp_test::bodies)

    printf '%s\n' "${resps[1]}" > "${tmp_dir}/h.json"
    testframework::assert_command "jq -e '.result.contents.value | contains(\"str::slice\")' '${tmp_dir}/h.json'" "lsp didChange updates the buffer"

    rm -rf "${tmp_dir}"
}

test_lsp_description_search() {
    # Natural-language completion: `?query` or a comment line.
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local out
    out="$(
        {
            lsp_test::frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
            lsp_test::frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/q.sh","languageId":"shell","version":1,"text":"?обрезать строку\n# обрезать пробелы по краям\n?slc\n?обрезать пробелы\n"}}}'
            # ?query в коде: "обрезать строку" / ?query in code
            lsp_test::frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/q.sh"},"position":{"line":0,"character":16}}}'
            # внутри комментария: "обрезать пробелы" / inside a comment
            lsp_test::frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/q.sh"},"position":{"line":1,"character":27}}}'
            # fuzzy по имени: подпоследовательность "slc" / name subsequence
            lsp_test::frame '{"jsonrpc":"2.0","id":4,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/q.sh"},"position":{"line":2,"character":4}}}'
            # точная фраза из описания: "обрезать пробелы" / exact description phrase
            lsp_test::frame '{"jsonrpc":"2.0","id":5,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/q.sh"},"position":{"line":3,"character":17}}}'
            lsp_test::frame '{"jsonrpc":"2.0","id":6,"method":"shutdown","params":null}'
            lsp_test::frame '{"jsonrpc":"2.0","method":"exit","params":null}'
        } | lsp::server 2>/dev/null
    )" || true

    local -a resps=()
    local b
    while IFS= read -r b; do
        resps+=("${b}")
    done < <(printf '%s' "${out}" | lsp_test::bodies)

    local i
    for i in "${!resps[@]}"; do
        printf '%s\n' "${resps[$i]}" > "${tmp_dir}/s${i}.json"
    done

    # "?обрезать строку" — ищем по описанию
    testframework::assert_command "jq -e '[.result.items[].label] | any(contains(\"slice\"))' '${tmp_dir}/s1.json'" "lsp ?query finds str::slice by description"

    # внутри комментария "обрезать пробелы" — комментарий как запрос
    testframework::assert_command "jq -e '[.result.items[].label] | any(contains(\"trim\"))' '${tmp_dir}/s2.json'" "lsp comment query finds str::trim"

    # "?обрезать пробелы" — точная фраза из описания / exact description phrase
    testframework::assert_command "jq -e '[.result.items[].label] | any(contains(\"trim\"))' '${tmp_dir}/s4.json'" "lsp exact description query finds str::trim"

    # "?slc" — подпоследовательность имени / subsequence of the name
    testframework::assert_command "jq -e '[.result.items[].label] | any(contains(\"slice\"))' '${tmp_dir}/s3.json'" "lsp fuzzy name subsequence finds slice"

    rm -rf "${tmp_dir}"
}

main() {
    print_header "LSP Unit Tests / Модульные тесты LSP"

    testframework::init

    if ! is::command jq; then
        echo "  SKIP: jq not available — LSP tests skipped"
        testframework::summary
        return 0
    fi

    testframework::section "Session / Сессия"
    test_lsp_session

    testframework::section "Open file functions / Функции открытого файла"
    test_lsp_open_file_functions

    testframework::section "Document sync / Синхронизация документов"
    test_lsp_did_change

    testframework::section "Description search / Поиск по описанию"
    test_lsp_description_search

    testframework::summary
}

main "$@"