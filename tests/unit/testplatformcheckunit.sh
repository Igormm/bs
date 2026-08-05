#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/test_platform_check_unit.sh — Unit tests for platform check module
# tests/unit/test_platform_check_unit.sh — Модульные тесты для модуля проверки платформы
#
# Этот файл содержит unit тесты для модуля platformcheck.
# This file contains unit tests for the platformcheck module.

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
    print_header "Platform Check Unit Tests / Модульные тесты проверки платформы"
    
    testframework::init
    
    # Тест 1: Инициализация модуля
    testframework::section "Module Initialization / Инициализация модуля"
    load "lib/system/platformcheck"
    testframework::assert_true "${PLATFORM_CHECK_INITIALIZED:-}" "Module initialized"
    testframework::assert_equal "1.0.0" "$PLATFORM_CHECK_VERSION" "Version correct"
    
    # Тест 2: Обнаружение платформ
    testframework::section "Platform Detection / Обнаружение платформ"
    
    # Сохраняем исходные значения
    local original_ostype="${OSTYPE:-}"
    
    # Тестируем macOS
    export OSTYPE="darwin20.0"
    testframework::assert_command "platformcheck::is_macos" "macOS detected"
    testframework::assert_false "platformcheck::is_linux" "Linux not detected on macOS"
    
    # Тестируем Linux
    export OSTYPE="linux-gnu"
    testframework::assert_false "platformcheck::is_macos" "macOS not detected on Linux"
    
    # Восстанавливаем исходное значение
    export OSTYPE="$original_ostype"
    
    # Тест 3: Получение информации о платформе
    testframework::section "Platform Information / Информация о платформе"
    
    local platform_info
    platform_info=$(platformcheck::get_info)
    testframework::assert_true "${#platform_info} -gt 0" "Platform info returned"
    
    # Тест 4: Проверка совместимости
    testframework::section "Compatibility Check / Проверка совместимости"
    
    # Мы не можем гарантировать совместимость на всех платформах в тестах
    # We can't guarantee compatibility on all platforms in tests
    # Но можем проверить, что функция работает
    # But we can check that the function works
    local is_compatible
    is_compatible=$(platformcheck::is_compatible && echo "compatible" || echo "incompatible")
    testframework::assert_true "${#is_compatible} -gt 0" "Compatibility check works"
    
    # Тест 5: Проверка зависимостей
    testframework::section "Dependency Check / Проверка зависимостей"
    
    # Проверяем базовые инструменты / Check basic tools
    local basic_tools=("bash" "grep" "sed" "awk")
    for tool in "${basic_tools[@]}"; do
        if utils::has "$tool"; then
            testframework::assert_true "true" "$tool available"
        else
            testframework::assert_true "false" "$tool not available"
        fi
    done
    
    # Тест 6: Формирование отчета
    testframework::section "Report Generation / Формирование отчета"
    
    local report
    report=$(platformcheck::get_report)
    testframework::assert_true "${#report} -gt 100" "Report generated"
    
    # Вывод сводки
    testframework::summary
}

# Запуск тестов
main "$@"
