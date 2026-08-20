#!/usr/bin/env bs
# shellcheck shell=bash
# tests/testframework.sh — Basic test framework for BS
# tests/testframework.sh — Базовый тестовый фреймворк для BS
#
# Этот файл предоставляет базовые функции для написания тестов.
# This file provides basic functions for writing tests.

set -euo pipefail

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Счетчики тестов
declare -g tests_run=0
declare -g tests_passed=0
declare -g tests_failed=0

# Заголовок
# @description Print a header banner
# @param $1 Header text / Текст заголовка
# @description Print a header banner (Unicode box / рамка Unicode)
# @param $1 Header text / Текст заголовка
print_header() {
    local text="$1"
    local inner=" ${text} "
    local line
    printf -v line '%*s' "${#inner}" ''
    line="${line// /─}"
    echo -e "${BLUE}╭${line}╮${NC}"
    echo -e "${BLUE}│${inner}│${NC}"
    echo -e "${BLUE}╰${line}╯${NC}"
    echo
}

# Функция инициализации тестов
# @description Initialize test framework
# @example testframework::init
testframework::init() {
    echo -e "${BLUE}Initializing test framework / Инициализация тестового фреймворка${NC}"
    tests_run=0
    tests_passed=0
    tests_failed=0
}

# Функция проверки условия
# @description Assert that condition is true
# @param $1 Condition to check: "true"/"false" or a [[ ... ]] expression / Условие для проверки
# @param $2 Test name / Название теста
# @example testframework::assert_true "$result" "Test result"
testframework::assert_true() {
    local condition="$1"
    local test_name="${2:-Unknown test}"
    
    ((++tests_run))
    
    # "true"/"false" обрабатываем явно, остальное — как выражение [[ ... ]]
    # Handle "true"/"false" explicitly, anything else as a [[ ... ]] expression
    local result=1
    if [[ "$condition" == "true" ]]; then
        result=0
    elif [[ "$condition" == "false" ]]; then
        result=1
    elif eval "[[ ${condition} ]]" 2>/dev/null; then
        result=0
    fi
    
    if [[ $result -eq 0 ]]; then
        echo -e "  ${GREEN}✓ $test_name: PASSED${NC}"
        ((++tests_passed))
        return 0
    else
        echo -e "  ${RED}✗ $test_name: FAILED${NC}"
        echo -e "    ${RED}Expected true, got: $condition${NC}"
        ((++tests_failed))
        return 1
    fi
}

# Функция проверки, что команда завершается с ошибкой
# @description Assert that command/condition fails
# @param $1 Command to run (or "false"/"true") / Команда для выполнения
# @param $2 Test name / Название теста
# @example testframework::assert_false "platformcheck::is_macos" "Not macOS"
testframework::assert_false() {
    local condition="$1"
    local test_name="${2:-Unknown test}"
    
    ((++tests_run))
    
    local result=1
    if [[ "$condition" == "false" ]]; then
        result=0
    elif [[ "$condition" == "true" ]]; then
        result=1
    elif ! eval "${condition}" >/dev/null 2>&1; then
        result=0
    fi
    
    if [[ $result -eq 0 ]]; then
        echo -e "  ${GREEN}✓ $test_name: PASSED${NC}"
        ((++tests_passed))
        return 0
    else
        echo -e "  ${RED}✗ $test_name: FAILED${NC}"
        echo -e "    ${RED}Expected failure, but succeeded: $condition${NC}"
        ((++tests_failed))
        return 1
    fi
}

# Функция проверки равенства
# @description Assert that two values are equal
# @param $1 Expected value / Ожидаемое значение
# @param $2 Actual value / Фактическое значение
# @param $3 Test name / Название теста
# @example testframework::assert_equal "expected" "$result" "Test equality"
testframework::assert_equal() {
    local expected="$1"
    local actual="$2"
    local test_name="${3:-Unknown test}"
    
    ((++tests_run))
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}✓ $test_name: PASSED${NC}"
        ((++tests_passed))
        return 0
    else
        echo -e "  ${RED}✗ $test_name: FAILED${NC}"
        echo -e "    ${RED}Expected: '$expected'${NC}"
        echo -e "    ${RED}Got:      '$actual'${NC}"
        ((++tests_failed))
        return 1
    fi
}

# Функция проверки существования файла
# @description Assert that file exists
# @param $1 File path / Путь к файлу
# @param $2 Test name / Название теста
# @example testframework::assert_file_exists "/path/to/file" "File exists"
testframework::assert_file_exists() {
    local file="$1"
    local test_name="${2:-File exists}"
    
    if [[ -f "$file" ]]; then
        testframework::assert_true "true" "$test_name"
    else
        testframework::assert_true "false" "$test_name"
    fi
}

# Функция проверки команды
# @description Assert that command succeeds
# @param $1 Command to run / Команда для выполнения
# @param $2 Test name / Название теста
# @example testframework::assert_command "ls /tmp" "List tmp directory"
testframework::assert_command() {
    local command="$1"
    local test_name="${2:-Command test}"
    
    if eval "$command" >/dev/null 2>&1; then
        testframework::assert_true "true" "$test_name"
    else
        testframework::assert_true "false" "$test_name"
    fi
}

# Функция вывода заголовка теста
# @description Print test section header
# @param $1 Section name / Название раздела
# @example testframework::section "Testing Logger"
testframework::section() {
    local section_name="$1"
    local line
    printf -v line '%*s' "$((${#section_name} + 2))" ''
    line="${line// /─}"
    echo
    echo -e "${BLUE}▶ ${section_name}${NC}"
    echo -e "${BLUE}${line}${NC}"
}

# Функция вывода сводки тестов
# @description Print test summary
# @example testframework::summary
testframework::summary() {
    echo
    print_header "TEST SUMMARY / СВОДКА ТЕСТОВ"
    echo -e "${BLUE}Tests run / Тестов запущено:${NC} $tests_run"
    echo -e "${GREEN}Passed / Пройдено:${NC} $tests_passed"
    echo -e "${RED}Failed / Провалено:${NC} $tests_failed"
    echo
    
    if [[ $tests_failed -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        echo -e "${GREEN}🎉 Все тесты пройдены!${NC}"
        return 0
    else
        echo -e "${RED}❌ Some tests failed!${NC}"
        echo -e "${RED}❌ Некоторые тесты провалены!${NC}"
        return 1
    fi
}

# Пример использования
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Этот файл запущен напрямую, демонстрируем использование
    # This file is run directly, demonstrate usage
    
    # Пути от расположения скрипта, чтобы демо работало из любого каталога
    # Paths relative to the script location so the demo works from any directory
    TESTFRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    BS_ROOT_DIR="$(cd "${TESTFRAMEWORK_DIR}/.." && pwd)"
    
    print_header "Test Framework Demo / Демонстрация тестового фреймворка"
    
    testframework::init
    
    # Тесты файловой системы
    testframework::section "Filesystem Tests / Тесты файловой системы"
    testframework::assert_file_exists "${BS_ROOT_DIR}/boot.sh" "Boot file exists"
    testframework::assert_file_exists "${BS_ROOT_DIR}/bs" "Main entrypoint exists"
    testframework::assert_file_exists "nonexistent" "Non-existent file test"
    
    # Тесты команд
    testframework::section "Command Tests / Тесты команд"
    testframework::assert_command "ls -la '${BS_ROOT_DIR}/boot.sh'" "List boot file"
    testframework::assert_command "pwd" "Print working directory"
    testframework::assert_command "false" "Failing command test"
    
    # Тесты равенства
    testframework::section "Equality Tests / Тесты равенства"
    testframework::assert_equal "test" "test" "String equality"
    testframework::assert_equal "1" "1" "Number equality"
    testframework::assert_equal "expected" "actual" "Failing equality test"
    
    # Вывод сводки
    testframework::summary
fi
