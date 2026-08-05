#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testllmunit.sh — Unit tests for lib/integration/llm
# tests/unit/testllmunit.sh — Модульные тесты LLM-клиента BS

set -euo pipefail

# Подключаем тестовый фреймворк / Source test framework
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Инициализируем BS / Initialize BS
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Подключаем тестируемый модуль / Load module under test
load "lib/integration/llm"

main() {
    print_header "LLM Client Unit Tests"
    print_header "Модульные тесты LLM-клиента"

    testframework::init

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    # ==========================================
    # providers
    # ==========================================
    testframework::section "providers"

    testframework::assert_command "source ${BS_PROJECT_ROOT}/lib/integration/llm.sh; llm::providers | grep -q openai" "llm::providers includes openai"
    testframework::assert_command "source ${BS_PROJECT_ROOT}/lib/integration/llm.sh; llm::providers | grep -q ollama" "llm::providers includes ollama"

    # ==========================================
    # validate provider
    # ==========================================
    testframework::section "validate provider"

    testframework::assert_command "source ${BS_PROJECT_ROOT}/lib/integration/llm.sh; __llm::validate_provider openai" "openai is valid provider"
    testframework::assert_command "source ${BS_PROJECT_ROOT}/lib/integration/llm.sh; __llm::validate_provider ollama" "ollama is valid provider"
    testframework::assert_false "source ${BS_PROJECT_ROOT}/lib/integration/llm.sh; __llm::validate_provider unknown" "unknown provider is invalid"

    # ==========================================
    # json escape
    # ==========================================
    testframework::section "json escape"

    testframework::assert_equal 'hello' "$(source ${BS_PROJECT_ROOT}/lib/integration/llm.sh; __llm::json_escape 'hello')" "json_escape preserves simple string"
    testframework::assert_equal 'line1\nline2' "$(source ${BS_PROJECT_ROOT}/lib/integration/llm.sh; __llm::json_escape $'line1\nline2')" "json_escape escapes newline"

    # ==========================================
    # request body builders
    # ==========================================
    testframework::section "request body builders"

    local openai_body
    openai_body="$(source ${BS_PROJECT_ROOT}/lib/integration/llm.sh; __llm::openai_body gpt-test 'Hello world')"
    testframework::assert_command "printf '%s' '${openai_body}' | grep -q 'gpt-test'" "openai body contains model"
    testframework::assert_command "printf '%s' '${openai_body}' | grep -q 'Hello world'" "openai body contains message"

    local ollama_body
    ollama_body="$(source ${BS_PROJECT_ROOT}/lib/integration/llm.sh; __llm::ollama_body llama3 'Hi')"
    testframework::assert_command "printf '%s' '${ollama_body}' | grep -q 'llama3'" "ollama body contains model"
    testframework::assert_command "printf '%s' '${ollama_body}' | grep -q 'stream'" "ollama body disables streaming"

    # ==========================================
    # chat dry-run
    # ==========================================
    testframework::section "chat dry-run"

    export FRAMEWORK_DRY_RUN=true
    local chat_response
    chat_response="$(llm::chat openai gpt-test 'Hello')"
    testframework::assert_equal '{"dry_run":true,"provider":"openai"}' "${chat_response}" "llm::chat dry-run returns stub"
    unset FRAMEWORK_DRY_RUN

    # ==========================================
    # chat missing key
    # ==========================================
    testframework::section "chat missing key"

    local rc=0
    OPENAI_API_KEY="" llm::chat openai gpt-test "Hello" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${INTEGRATION_ERROR_LLM}" "${rc}" "llm::chat fails without OpenAI key"

    # ==========================================
    # chat_file
    # ==========================================
    testframework::section "chat_file"

    local test_file="${tmp_dir}/prompt.txt"
    printf 'Explain this file' > "${test_file}"

    export FRAMEWORK_DRY_RUN=true
    local file_response
    file_response="$(llm::chat_file ollama llama3 "${test_file}")"
    testframework::assert_equal '{"dry_run":true,"provider":"ollama"}' "${file_response}" "llm::chat_file dry-run works"
    unset FRAMEWORK_DRY_RUN

    rc=0
    llm::chat_file ollama llama3 "${tmp_dir}/missing.txt" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "llm::chat_file fails on missing file"

    # ==========================================
    # json_query fallback
    # ==========================================
    testframework::section "json_query"

    testframework::assert_equal 'hello' "$(source ${BS_PROJECT_ROOT}/lib/integration/llm.sh; __llm::json_query '{"choices":[{"message":{"content":"hello"}}]}' '.choices[0].message.content')" "json_query extracts openai content"
    testframework::assert_equal 'world' "$(source ${BS_PROJECT_ROOT}/lib/integration/llm.sh; __llm::json_query '{"message":{"content":"world"}}' '.message.content')" "json_query extracts ollama content"

    # ==========================================
    # Cleanup and summary
    # ==========================================
    rm -rf "${tmp_dir}"

    testframework::summary
}

main "$@"
