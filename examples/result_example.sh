#!/usr/bin/env bs
# shellcheck shell=bash
# examples/result_example.sh — JSON result contract demo for BS integrations
# Пример JSON-контракта результата для интеграций BS (Go backend и др.).

set -euo pipefail

load "core/utils"
load "lib/io/files"
load "lib/integration/result"

main() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    echo "Working in: ${tmp_dir}"

    # ==========================================
    # 1. Run external command and get JSON result
    # Запуск внешней команды и получение JSON-результата
    # ==========================================
    echo "--- 1. result::run echo ---"
    result::run -- echo "hello from BS"

    # ==========================================
    # 2. Capture a failing command
    # Перехват неудачной команды
    # ==========================================
    echo ""
    echo "--- 2. result::run failing command ---"
    result::run -- ls /nonexistent_path_12345 || true

    # ==========================================
    # 3. Wrap a BS function
    # Обёртка функции BS
    # ==========================================
    echo ""
    echo "--- 3. result::wrap io::files::copy_file ---"
    printf 'content\n' > "${tmp_dir}/src.txt"
    result::wrap io::files::copy_file "${tmp_dir}/src.txt" "${tmp_dir}/dst.txt"

    # ==========================================
    # 4. Write result to a file (for Go backend)
    # Запись результата в файл (для Go backend)
    # ==========================================
    echo ""
    echo "--- 4. BS_RESULT_FILE ---"
    local result_file="${tmp_dir}/result.json"
    BS_RESULT_FILE="${result_file}" result::run -- uname -a
    echo "Result written to: ${result_file}"
    cat "${result_file}"

    # ==========================================
    # 5. Parse result inside bash (for scripts)
    # Разбор результата внутри bash (для скриптов)
    # ==========================================
    echo ""
    echo "--- 5. result::get / result::is_success ---"
    local json
    json="$(result::run -- true)"

    local exit_code
    result::get "${json}" "exit_code" exit_code
    echo "Parsed exit_code: ${exit_code}"

    if result::is_success "${json}"; then
        echo "Operation succeeded"
    else
        echo "Operation failed"
    fi

    echo ""
    echo "Done. Inspect ${tmp_dir} or remove it manually."
}

main "$@"
