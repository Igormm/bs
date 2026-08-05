#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testprocessunit.sh — Unit tests for lib/io/process
# tests/unit/testprocessunit.sh — Модульные тесты для Process Guard

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
load "lib/io/process"

main() {
    print_header "IO Process Guard Unit Tests"
    print_header "Модульные тесты Process Guard"

    testframework::init

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    # ==========================================
    # Normal exit / Нормальное завершение
    # ==========================================
    testframework::section "Normal execution"

    local rc=0
    io::process::guard --timeout 5 -- true || rc=$?
    testframework::assert_equal "0" "${rc}" "guard returns 0 for successful command"

    rc=0
    io::process::guard --timeout 5 -- bash -c 'exit 7' || rc=$?
    testframework::assert_equal "7" "${rc}" "guard preserves command exit code"

    # ==========================================
    # Timeout / Таймаут
    # ==========================================
    testframework::section "Timeout"

    local diag_dir="${tmp_dir}/timeout_diag"
    mkdir -p "${diag_dir}"

    rc=0
    io::process::guard --timeout 1 --diagnostic-dir "${diag_dir}" -- sleep 5 || rc=$?
    testframework::assert_equal "${IO_PROCESS_EXIT_TIMEOUT}" "${rc}" "guard returns TIMEOUT on timeout"
    testframework::assert_command "test -f '${diag_dir}/report.log'" "timeout creates diagnostic report"
    testframework::assert_command "grep -q 'Reason: timeout' '${diag_dir}/report.log'" "report mentions timeout reason"

    # ==========================================
    # Hang detection / Обнаружение зависания
    # ==========================================
    testframework::section "Hang detection"

    diag_dir="${tmp_dir}/hang_diag"
    mkdir -p "${diag_dir}"

    rc=0
    io::process::guard --timeout 0 --hang-after 1 --diagnostic-dir "${diag_dir}" -- sleep 5 || rc=$?
    testframework::assert_equal "${IO_PROCESS_EXIT_HANG}" "${rc}" "guard returns HANG on silent process"
    testframework::assert_command "test -f '${diag_dir}/report.log'" "hang creates diagnostic report"
    testframework::assert_command "grep -q 'Reason: hang' '${diag_dir}/report.log'" "report mentions hang reason"

    # ==========================================
    # Output prevents hang / Вывод предотвращает hang
    # ==========================================
    testframework::section "Output activity prevents hang"

    rc=0
    io::process::guard --timeout 0 --hang-after 1 --timeout 3 -- bash -c 'for i in 1 2 3; do echo tick; sleep 0.6; done' || rc=$?
    testframework::assert_equal "0" "${rc}" "regular output prevents hang detection"

    # ==========================================
    # Strace availability / Наличие strace
    # ==========================================
    testframework::section "Strace diagnostics"

    if utils::has strace && utils::has sudo && sudo -n true 2>/dev/null; then
        diag_dir="${tmp_dir}/strace_diag"
        mkdir -p "${diag_dir}"

        rc=0
        io::process::guard --timeout 0 --hang-after 1 --diagnostic-dir "${diag_dir}" --strace-file -- sleep 5 || rc=$?
        testframework::assert_command "test -f '${diag_dir}/strace_file.log'" "strace file trace is created"
    else
        log::warn "Skipping strace test: strace or passwordless sudo not available"
    fi

    # ==========================================
    # Dry-run / Сухой прогон
    # ==========================================
    testframework::section "Dry-run mode"

    export FRAMEWORK_DRY_RUN=true
    rc=0
    io::process::guard --timeout 1 -- sleep 5 || rc=$?
    unset FRAMEWORK_DRY_RUN
    testframework::assert_equal "0" "${rc}" "dry-run does not run the command"

    # ==========================================
    # Invalid arguments / Неверные аргументы
    # ==========================================
    testframework::section "Argument validation"

    rc=0
    io::process::guard --timeout abc -- true || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "invalid timeout value rejected"

    rc=0
    io::process::guard || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "missing command rejected"

    # ==========================================
    # Cleanup
    # ==========================================
    rm -rf "${tmp_dir}"

    testframework::summary
}

main "$@"
