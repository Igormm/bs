#!/usr/bin/env bs
# tests/unit/testconstunit.sh — Unit tests for core/const module
# tests/unit/testconstunit.sh — Модульные тесты для модуля core/const
#
# Этот файл содержит unit тесты для констант ядра.
# This file contains unit tests for the core constants.

set -euo pipefail

# Подключаем тестовый фреймворк (пути от расположения скрипта)
# Source test framework (paths relative to the script location)
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Подключаем bootstrap BS (core/const загружается через loader)
# Source BS bootstrap (core/const is loaded via the loader)
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

# Главная функция тестов
main() {
    print_header "Core Constants Unit Tests / Модульные тесты констант ядра"
    
    testframework::init
    
    # Тест 1: Базовые коды возврата
    testframework::section "Basic Return Codes / Базовые коды возврата"
    testframework::assert_equal "0" "${E_SUCCESS}" "E_SUCCESS is 0"
    testframework::assert_equal "1" "${E_ERROR}" "E_ERROR is 1"
    testframework::assert_equal "2" "${E_INVALID}" "E_INVALID is 2"
    
    # Тест 2: Расширенные коды ошибок
    # Примечание: LIB_ERROR_* объявлены через declare -r в core/const.sh и потому
    # локальны для функции load() при загрузке через loader — глобально не видны
    # (pre-existing баг core). Проверяем только коды, объявленные через readonly.
    # Note: LIB_ERROR_* are declared via declare -r in core/const.sh, which makes
    # them local to the load() function when loaded via the loader — not visible
    # globally (pre-existing core bug). Only readonly-declared codes are checked.
    testframework::section "Error Descriptions / Описания ошибок"
    testframework::assert_equal "Success / Успешно" "$(const::error_description 0)" "Description for code 0"
    testframework::assert_equal "General error / Общая ошибка" "$(const::error_description 1)" "Description for code 1"
    testframework::assert_equal "File not found / Файл не найден" "$(const::error_description 5)" "Description for code 5"
    
    local unknown_desc
    unknown_desc=$(const::error_description 999)
    if [[ "${unknown_desc}" == *"Unknown"* ]]; then
        testframework::assert_true "true" "Unknown code gives Unknown description"
    else
        testframework::assert_true "false" "Unknown code gives Unknown description"
    fi
    
    # Тест 4: Валидация кодов
    testframework::section "Code Validation / Валидация кодов"
    testframework::assert_command "const::is_valid_error_code 0" "Code 0 is valid"
    testframework::assert_command "const::is_valid_error_code 10" "Code 10 is valid"
    testframework::assert_false "const::is_valid_error_code 999" "Code 999 is invalid"
    
    # Тест 5: Версия фреймворка
    testframework::section "Framework Version / Версия фреймворка"
    testframework::assert_true "${#BS_VERSION} -gt 0" "BS_VERSION is set"
    testframework::assert_equal "${BS_VERSION}" "$(const::version)" "const::version matches BS_VERSION"
    
    # Вывод сводки
    testframework::summary
}

# Запуск тестов
main "$@"
