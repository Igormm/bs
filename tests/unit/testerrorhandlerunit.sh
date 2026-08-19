#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testerrorhandlerunit.sh — Unit tests for core/errorhandler module
# tests/unit/testerrorhandlerunit.sh — Модульные тесты для модуля core/errorhandler
#
# Этот файл содержит unit тесты для обработчика ошибок ядра.
# This file contains unit tests for the core error handler.

set -euo pipefail

# Подключаем тестовый фреймворк (пути от расположения скрипта)
# Source test framework (paths relative to the script location)
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Подключаем bootstrap BS (core/errorhandler загружается через loader)
# Source BS bootstrap (core/errorhandler is loaded via the loader)
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

# Главная функция тестов
main() {
    print_header "Error Handler Unit Tests / Модульные тесты обработчика ошибок"
    
    testframework::init
    
    # Тест 1: errorhandler::throw возвращает переданный код
    testframework::section "Throw Return Codes / Коды возврата throw"
    
    local rc=0
    utils::quiet_err errorhandler::throw "test::func" "Test error" 5 || rc=$?
    testframework::assert_equal "5" "$rc" "throw returns the given code"
    
    rc=0
    utils::quiet_err errorhandler::throw "test::func" "Test error" || rc=$?
    testframework::assert_equal "1" "$rc" "throw defaults to E_ERROR (1)"
    
    # Тест 2: errorhandler::throw не завершает shell
    testframework::section "Throw Does Not Exit / throw не завершает shell"
    
    local marker=""
    utils::quiet_err errorhandler::throw "test::func" "Test error" 7 || true
    marker="still alive"
    testframework::assert_equal "still alive" "$marker" "Shell continues after throw"
    
    # Тест 3: errorhandler::throw пишет в лог
    testframework::section "Throw Logging / Логирование throw"
    
    local throw_out
    throw_out=$(errorhandler::throw "test::func" "something failed" 3 2>&1 || true)
    if echo "${throw_out}" | grep -q "test::func"; then
        testframework::assert_true "true" "throw logs the function name"
    else
        testframework::assert_true "false" "throw logs the function name"
    fi
    
    # Тест 3b: error::throw подставляет имя вызывающей функции сам
    testframework::section "error::throw Auto Name / Авто-имя в error::throw"
    
    test::auto_name() {
        error::throw "auto fail" 9
    }
    
    local auto_out rc=0
    auto_out=$(test::auto_name 2>&1) || rc=$?
    testframework::assert_equal "9" "${rc}" "error::throw returns the given code"
    if echo "${auto_out}" | grep -q "test::auto_name"; then
        testframework::assert_true "true" "error::throw detects the caller name"
    else
        testframework::assert_true "false" "error::throw detects the caller name"
    fi
    
    # Тест 4: cleanup-стек идемпотентен
    testframework::section "Cleanup Stack / Стек очистки"
    
    local tmp_file
    tmp_file=$(mktemp)
    
    test::cleanup_marker() {
        echo "cleaned" >> "${tmp_file}"
    }
    
    cleanup::add "test::cleanup_marker"
    testframework::assert_true "${#BS_CLEANUP_STACK[@]} -eq 1" "Cleanup function added to stack"
    
    cleanup::__run_all
    cleanup::__run_all
    
    local lines
    lines=$(wc -l < "${tmp_file}")
    testframework::assert_equal "1" "$lines" "Cleanup ran exactly once (idempotent)"
    testframework::assert_true "${#BS_CLEANUP_STACK[@]} -eq 0" "Cleanup stack empty after run"
    
    rm -f "${tmp_file}"
    unset -f test::cleanup_marker
    
    # Тест 5: log::fatal возвращает код, не завершая shell
    testframework::section "Fatal Returns Code / fatal возвращает код"
    
    rc=0
    utils::quiet_err log::fatal "Test fatal message" || rc=$?
    testframework::assert_equal "1" "$rc" "log::fatal returns E_ERROR"
    
    marker=""
    utils::quiet_err log::fatal "Test fatal message" || true
    marker="still alive"
    testframework::assert_equal "still alive" "$marker" "Shell continues after log::fatal"
    
    # Вывод сводки
    testframework::summary
}

# Запуск тестов
main "$@"
