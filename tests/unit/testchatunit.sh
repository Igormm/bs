#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testchatunit.sh — Unit tests for lib/integration/chat (LLM mock)
# tests/unit/testchatunit.sh — Модульные тесты для lib/integration/chat (мок LLM)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/integration/llm"
load "lib/integration/chat"

test_build_messages() {
    local json
    json="$(chat::message user "привет \"мир\"")"
    testframework::assert_equal '{"role":"user","content":"привет \"мир\""}' "${json}" "chat::message escapes JSON"

    json="$(chat::build_messages "sys prompt" "$(chat::message user "u1")" "$(chat::message assistant "a1")" "$(chat::message user "u2")")"
    testframework::assert_equal "4" "$(printf '%s' "${json}" | jq 'length')" "chat::build_messages count"
    testframework::assert_equal "sys prompt" "$(printf '%s' "${json}" | jq -r '.[0].content')" "chat::build_messages system first"
    testframework::assert_equal "u2" "$(printf '%s' "${json}" | jq -r '.[-1].content')" "chat::build_messages user last"

    json="$(chat::build_messages "" "$(chat::message user "x")")"
    testframework::assert_equal "1" "$(printf '%s' "${json}" | jq 'length')" "chat::build_messages empty system skipped"
}

test_chat_turn() {
    export LLM_MOCK_RESPONSE='{"choices":[{"message":{"content":"привет от мока"}}]}'
    local msgs
    msgs="$(chat::build_messages "" "$(chat::message user "hi")")"
    testframework::assert_equal "привет от мока" "$(llm::chat_turn openai mock-model "${msgs}")" "llm::chat_turn extracts openai content"
    unset LLM_MOCK_RESPONSE
}

test_repl_one_shot() {
    export LLM_MOCK_RESPONSE='{"message":{"content":"локальный ответ"}}'
    local out
    out="$(chat::repl ollama mock-model "sys" "скажи привет" 2>/dev/null)" || true
    testframework::assert_equal "локальный ответ" "$(printf '%s\n' "${out}" | head -1)" "chat::repl one-shot returns model reply"
    unset LLM_MOCK_RESPONSE
}

test_repl_interactive() {
    export LLM_MOCK_RESPONSE='{"message":{"content":"ответ N"}}'
    local out
    out="$(
        printf '/help\n/quit\n' | chat::repl ollama mock-model "sys" "" 20 2>/dev/null
    )" || true
    testframework::assert_command "printf '%s' '${out}' | grep -q '/quit, /exit'" "chat::repl help lists commands"
    unset LLM_MOCK_RESPONSE
}

main() {
    print_header "Chat Unit Tests / Модульные тесты чата"

    testframework::init

    if ! is::command jq; then
        echo "  SKIP: jq not available — chat tests skipped"
        testframework::summary
        return 0
    fi

    testframework::section "Messages / Сообщения"
    test_build_messages

    testframework::section "LLM turn / Ход LLM"
    test_chat_turn

    testframework::section "REPL / Чат"
    test_repl_one_shot
    test_repl_interactive

    testframework::summary
}

main "$@"