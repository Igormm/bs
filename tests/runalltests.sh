#!/usr/bin/env bs
# tests/runalltests.sh — Comprehensive test runner for BS framework
# tests/runalltests.sh — Комплексный запуск всех тестов фреймворка BS
#
# Этот скрипт запускает все тесты фреймворка и выводит подробный отчет.
# This script runs all framework tests and outputs a detailed report.

set -euo pipefail

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Заголовок тестов
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

# Счетчики тестов
declare -i total_tests=0
declare -i passed_tests=0
declare -i failed_tests=0

# Функция запуска теста
# @description Run a test and track results
# @param $1 Test name / Название теста
# @param $2 Test script / Скрипт теста
# @return 0 if test passed, 1 if failed
run_test() {
    local test_name="$1"
    local test_script="$2"
    
    ((total_tests++))
    echo -e "${YELLOW}▶ Running test:${NC} $test_name"
    echo "----------------------------------------"
    
    # Делаем скрипт исполняемым
    chmod +x "$test_script" 2>/dev/null || true
    
    if "./$test_script"; then
        echo -e "${GREEN}✓ $test_name: PASSED${NC}"
        ((passed_tests++))
        echo
        return 0
    else
        echo -e "${RED}✗ $test_name: FAILED${NC}"
        ((failed_tests++))
        echo
        return 1
    fi
}

# Основная функция тестирования
main() {
    print_header "BS Framework Comprehensive Test Suite"
    print_header "Комплексный набор тестов фреймворка BS"
    
    echo -e "${YELLOW}Starting test execution...${NC}"
    echo -e "${YELLOW}Запуск выполнения тестов...${NC}"
    echo
    
    # Запуск unit тестов
    if [[ -d "unit" ]]; then
        echo -e "${BLUE}Unit Tests:${NC}"
        echo -e "${BLUE}Модульные тесты:${NC}"
        for test_file in unit/*.sh; do
            if [[ -f "$test_file" ]]; then
                test_name=$(basename "$test_file" .sh)
                run_test "Unit: $test_name" "$test_file"
            fi
        done
    fi
    
    # Запуск интеграционных тестов
    if [[ -d "integration" ]]; then
        echo -e "${BLUE}Integration Tests:${NC}"
        echo -e "${BLUE}Интеграционные тесты:${NC}"
        for test_file in integration/*.sh; do
            if [[ -f "$test_file" ]]; then
                test_name=$(basename "$test_file" .sh)
                run_test "Integration: $test_name" "$test_file"
            fi
        done
    fi
    
    # Запуск демо тестов
    if [[ -d "demos" ]]; then
        echo -e "${BLUE}Demo Tests:${NC}"
        echo -e "${BLUE}Демонстрационные тесты:${NC}"
        for test_file in demos/*.sh; do
            if [[ -f "$test_file" ]]; then
                test_name=$(basename "$test_file" .sh)
                run_test "Demo: $test_name" "$test_file"
            fi
        done
    fi
    
    # Запуск специальных тестов из корня
    if [[ -f "../run_comprehensive_test.sh" ]]; then
        echo -e "${BLUE}Framework Tests:${NC}"
        echo -e "${BLUE}Тесты фреймворка:${NC}"
        run_test "Comprehensive Framework" "../run_comprehensive_test.sh"
    fi
    
    # Сводка результатов
    print_header "TEST SUMMARY / СВОДКА ТЕСТОВ"
    
    echo -e "${BLUE}Total tests / Всего тестов:${NC} $total_tests"
    echo -e "${GREEN}Passed / Пройдено:${NC} $passed_tests"
    echo -e "${RED}Failed / Провалено:${NC} $failed_tests"
    echo
    
    if [[ $failed_tests -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        echo -e "${GREEN}🎉 Все тесты пройдены!${NC}"
        echo -e "${GREEN}BS framework is working correctly!${NC}"
        echo -e "${GREEN}Фреймворк BS работает корректно!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed!${NC}"
        echo -e "${RED}❌ Некоторые тесты провалены!${NC}"
        echo -e "${YELLOW}Please check the output above for details.${NC}"
        echo -e "${YELLOW}Пожалуйста, проверьте вывод выше для деталей.${NC}"
        exit 1
    fi
}

# Запуск основной функции
main "$@"
