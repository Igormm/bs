#!/usr/bin/env bs
# tests/unit/testversionunit.sh — Unit tests for core/version module
# tests/unit/testversionunit.sh — Модульные тесты для модуля core/version
#
# Этот файл содержит unit тесты для сравнения версий.
# This file contains unit tests for version comparison.

set -euo pipefail

# Подключаем тестовый фреймворк (пути от расположения скрипта)
# Source test framework (paths relative to the script location)
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Подключаем bootstrap BS (core/version загружается через loader)
# Source BS bootstrap (core/version is loaded via the loader)
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

# Главная функция тестов
main() {
    print_header "Version Unit Tests / Модульные тесты версий"
    
    testframework::init
    
    # Тест 1: Сравнение версий (0 — равны, 1 — первая больше, 2 — первая меньше)
    # Version comparison (0 — equal, 1 — first is greater, 2 — first is less)
    testframework::section "Version Compare / Сравнение версий"
    
    local rc=0
    bs::version::compare "0.3.0" "0.3.0" || rc=$?
    testframework::assert_equal "0" "$rc" "0.3.0 == 0.3.0"
    
    rc=0
    bs::version::compare "0.3.0" "0.10.0" || rc=$?
    testframework::assert_equal "2" "$rc" "0.3.0 < 0.10.0 (numeric, not lexicographic)"
    
    rc=0
    bs::version::compare "0.10.0" "0.3.0" || rc=$?
    testframework::assert_equal "1" "$rc" "0.10.0 > 0.3.0"
    
    rc=0
    bs::version::compare "1.0" "1.0.0" || rc=$?
    testframework::assert_equal "0" "$rc" "1.0 == 1.0.0"
    
    rc=0
    bs::version::compare "2.0.0" "1.9.9" || rc=$?
    testframework::assert_equal "1" "$rc" "2.0.0 > 1.9.9"
    
    # Тест 2: Получение версии
    testframework::section "Version Info / Информация о версии"
    testframework::assert_equal "${BS_VERSION}" "$(bs::version::get)" "bs::version::get matches BS_VERSION"
    
    local printed
    printed=$(bs::version::print)
    if [[ "${printed}" == *"${BS_VERSION}"* ]]; then
        testframework::assert_true "true" "bs::version::print contains version"
    else
        testframework::assert_true "false" "bs::version::print contains version"
    fi
    
    # Вывод сводки
    testframework::summary
}

# Запуск тестов
main "$@"
