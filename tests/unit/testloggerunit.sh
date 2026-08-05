#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/test_logger_unit.sh — Unit tests for logger module
# tests/unit/test_logger_unit.sh — Модульные тесты для модуля logger
#
# Этот файл содержит unit тесты для модуля logger.
# This file contains unit tests for the logger module.

set -euo pipefail

# Подключаем тестовый фреймворк (пути от расположения скрипта)
# Source test framework (paths relative to the script location)
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Подключаем bootstrap BS (ядро загружается через loader)
# Source BS bootstrap (core is loaded via the loader)
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

# lib-модули подключают core через BS_HOME (pre-existing расхождение BS_ROOT/BS_HOME)
# lib modules source core via BS_HOME (pre-existing BS_ROOT/BS_HOME mismatch)
export BS_HOME="${BS_PROJECT_ROOT}"

# Главная функция тестов
main() {
    print_header "Logger Unit Tests / Модульные тесты logger"
    
    testframework::init
    
    # Тест 1: Проверка загрузки модуля
    testframework::section "Module Loading / Загрузка модуля"
    load "core/logger"
    testframework::assert_true "${LOGGER_LOADED:-}" "Logger module loaded"
    
    # Тест 2: Проверка уровней логирования
    testframework::section "Log Levels / Уровни логирования"
    
    # Перенаправляем вывод для тестирования
    local output
    
    output=$(log::info "Test message" 2>&1)
    testframework::assert_true "${#output} -gt 0" "Info level produces output"
    
    output=$(log::debug "Debug message" 2>&1)
    # Debug не должен выводиться при уровне INFO
    testframework::assert_equal "" "$output" "Debug level silent at INFO level"
    
    # Тест 3: Форматирование
    testframework::section "Formatting / Форматирование"
    
    output=$(log::header "Test Header" 2>&1)
    testframework::assert_true "${#output} -gt 10" "Header produces output"
    
    # Тест 4: Переменные окружения
    testframework::section "Environment Variables / Переменные окружения"
    
    # Сохраняем исходные значения
    local original_level="${BS_LOG_LEVEL:-INFO}"
    local original_color="${BS_LOG_COLOR:-auto}"
    
    # Тестируем разные уровни
    export BS_LOG_LEVEL=DEBUG
    output=$(log::debug "Should appear" 2>&1)
    testframework::assert_true "${#output} -gt 0" "Debug visible at DEBUG level"
    
    export BS_LOG_LEVEL=ERROR
    output=$(log::info "Should not appear" 2>&1)
    testframework::assert_equal "" "$output" "Info hidden at ERROR level"
    
    # Восстанавливаем исходные значения
    export BS_LOG_LEVEL="$original_level"
    export BS_LOG_COLOR="$original_color"
    
    # Тест 5: Обработка ошибок
    testframework::section "Error Handling / Обработка ошибок"
    
    # Невалидный уровень логирования откатывается к INFO
    # Invalid log level falls back to INFO
    export BS_LOG_LEVEL=INVALID_LEVEL
    output=$(log::info "Fallback level message" 2>&1)
    testframework::assert_true "${#output} -gt 0" "Invalid level falls back to INFO"
    export BS_LOG_LEVEL="$original_level"
    
    # Вывод сводки
    testframework::summary
}

# Запуск тестов
main "$@"
