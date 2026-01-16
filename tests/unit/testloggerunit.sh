#!/usr/bin/env bs
# tests/unit/test_logger_unit.sh — Unit tests for logger module
# tests/unit/test_logger_unit.sh — Модульные тесты для модуля logger
#
# Этот файл содержит unit тесты для модуля logger.
# This file contains unit tests for the logger module.

set -euo pipefail

# Подключаем тестовый фреймворк
source "../testframework.sh"

# Подключаем тестируемый модуль
source "../../../boot.sh"
bs::init

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
    local original_level="${BOSA_LOG_LEVEL:-INFO}"
    local original_color="${BOSA_LOG_COLOR:-auto}"
    
    # Тестируем разные уровни
    export BOSA_LOG_LEVEL=DEBUG
    output=$(log::debug "Should appear" 2>&1)
    testframework::assert_true "${#output} -gt 0" "Debug visible at DEBUG level"
    
    export BOSA_LOG_LEVEL=ERROR
    output=$(log::info "Should not appear" 2>&1)
    testframework::assert_equal "" "$output" "Info hidden at ERROR level"
    
    # Восстанавливаем исходные значения
    export BOSA_LOG_LEVEL="$original_level"
    export BOSA_LOG_COLOR="$original_color"
    
    # Тест 5: Обработка ошибок
    testframework::section "Error Handling / Обработка ошибок"
    
    # Тестируем guard clauses
    output=$(log::info 2>&1 || echo "error")
    testframework::assert_equal "error" "$output" "Missing argument handling"
    
    # Вывод сводки
    testframework::summary
}

# Запуск тестов
main "$@"
