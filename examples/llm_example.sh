#!/usr/bin/env bs
# examples/llm_example.sh — LLM client demo
# Пример использования LLM-клиента BS.

set -euo pipefail

load "core/utils"
load "lib/integration/llm"

main() {
    echo "--- Supported providers ---"
    llm::providers
    echo ""

    echo "--- OpenAI availability (key required) ---"
    if llm::is_available openai; then
        echo "OpenAI is configured"
    else
        echo "OpenAI is not configured (set OPENAI_API_KEY)"
    fi

    echo ""
    echo "--- Ollama availability ---"
    if llm::is_available ollama; then
        echo "Ollama is reachable"
    else
        echo "Ollama is not reachable (set OLLAMA_HOST)"
    fi

    echo ""
    echo "--- Dry-run chat ---"
    export FRAMEWORK_DRY_RUN=true
    local response
    response="$(llm::chat openai gpt-3.5-turbo "Hello")"
    echo "Dry-run response: ${response}"
    unset FRAMEWORK_DRY_RUN

    echo ""
    echo "--- Structured result (dry-run) ---"
    export FRAMEWORK_DRY_RUN=true
    llm::result openai gpt-3.5-turbo "Hello"
    unset FRAMEWORK_DRY_RUN
}

main "$@"
