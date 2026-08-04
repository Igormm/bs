#!/usr/bin/env bs
# examples/processguard_example.sh — Process Guard usage demo
# Пример использования обёртки-сторожа io::process::guard.

set -euo pipefail

load "core/utils"
load "lib/io/process"

main() {
    local diag_dir
    diag_dir="$(mktemp -d)"
    echo "Diagnostics will be saved to: ${diag_dir}"

    # 1. Успешная быстрая команда / Fast successful command
    echo "--- Running: echo hello ---"
    io::process::guard --timeout 5 -- echo "hello"

    # 2. Искусственный таймаут / Artificial timeout
    echo "--- Running: sleep 10 with timeout 2 ---"
    local rc=0
    io::process::guard --timeout 2 --diagnostic-dir "${diag_dir}/timeout" -- sleep 10 || rc=$?
    echo "Timeout test exit code: ${rc} (expected ${IO_PROCESS_EXIT_TIMEOUT})"

    # 3. Искусственное зависание (нет вывода) / Artificial hang (no output)
    echo "--- Running: sleep 10 with hang-after 2 ---"
    rc=0
    io::process::guard --hang-after 2 --diagnostic-dir "${diag_dir}/hang" -- sleep 10 || rc=$?
    echo "Hang test exit code: ${rc} (expected ${IO_PROCESS_EXIT_HANG})"

    # 4. Процесс с редким выводом не должен считаться зависшим
    echo "--- Running: slow writer (hang-after 2, total 3s) ---"
    io::process::guard --timeout 5 --hang-after 2 -- bash -c 'for i in 1 2 3; do echo "tick ${i}"; sleep 1.1; done'

    echo ""
    echo "Inspect diagnostic reports in ${diag_dir}"
}

main "$@"
