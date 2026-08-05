#!/usr/bin/env bs
# shellcheck shell=bash
# examples/demo.sh — BS framework asciinema demo
# Короткая демонстрация возможностей BS для записи в asciinema.

set -euo pipefail

load "core/logger"
load "lib/integration/http"
load "lib/integration/llm"
load "lib/integration/k8s"
load "lib/integration/result"

# Helper to print a section header
__demo::section() {
    echo ""
    echo "==> $1"
}

main() {
    __demo::section "BS Framework demo"
    echo "Version: ${BS_VERSION}"

    __demo::section "HTTP client (dry-run)"
    export FRAMEWORK_DRY_RUN=true
    http::post "https://api.example.com/users" '{"name":"alice"}' --header "Content-Type: application/json"
    unset FRAMEWORK_DRY_RUN

    __demo::section "LLM client (dry-run)"
    export FRAMEWORK_DRY_RUN=true
    llm::chat openai gpt-3.5-turbo "Hello"
    unset FRAMEWORK_DRY_RUN

    __demo::section "Kubernetes wrapper (dry-run)"
    export FRAMEWORK_DRY_RUN=true
    k8s::pod::list
    k8s::deployment::restart my-app
    unset FRAMEWORK_DRY_RUN

    __demo::section "Structured result (JSON)"
    result::run -- uname -s

    __demo::section "Done"
}

main "$@"
