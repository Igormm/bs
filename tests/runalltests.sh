#!/usr/bin/env bs
# shellcheck shell=bash
# tests/runalltests.sh — Comprehensive test runner for BS framework
# tests/runalltests.sh — Комплексный запуск всех тестов фреймворка BS
#
# Этот скрипт запускает все тесты фреймворка и выводит подробный отчет.
# This script runs all framework tests and outputs a detailed report.
#
# Usage / Использование:
#   bash tests/runalltests.sh                # безопасный прогон (из любого каталога)
#   bash tests/runalltests.sh --with-root    # + деструктивные тесты (только под root)

set -euo pipefail

# Каталог скрипта: прогон работает из любого текущего каталога
# Script directory: the run works from any current directory
readonly RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${RUNNER_DIR}"

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
declare -i skipped_tests=0

# Разбор аргументов
with_root=0
for arg in "$@"; do
    case "${arg}" in
        --with-root) with_root=1 ;;
        -h|--help)
            echo "Usage: bash tests/runalltests.sh [--with-root]"
            echo "  --with-root  Также запустить root-требующие/деструктивные тесты (нужен root)"
            echo "               Also run root-requiring/destructive tests (requires root)"
            exit 0
            ;;
        *)
            echo "Unknown option: ${arg}" >&2
            exit 2
            ;;
    esac
done

# Деструктивные/root-требующие тесты (только с --with-root и EUID=0):
# Destructive/root-requiring tests (only with --with-root and EUID=0):
#  - integration/testwireguard.sh — пишет в /etc/wireguard, /var/backups, поднимает wg-интерфейсы (root)
#  - audit/testsystemaudit.sh — подменяет /etc/ssh/sshd_config и /etc/security/pwquality.conf (root)
declare -a ROOT_TESTS=(
    "integration/testwireguard.sh"
    "audit/testsystemaudit.sh"
)

is_root_test() {
    local file="$1"
    local root_test
    for root_test in "${ROOT_TESTS[@]}"; do
        [[ "${file}" == "${root_test}" ]] && return 0
    done
    return 1
}

# Функция пропуска теста
# @description Skip a test with an explicit message
skip_test() {
    local test_name="$1"
    local reason="$2"

    ((++total_tests))
    ((++skipped_tests))
    echo -e "${YELLOW}⊘ Skipping test:${NC} $test_name"
    echo -e "  ${YELLOW}Reason / Причина:${NC} $reason"
    echo
    return 0
}

# Функция запуска теста
# @description Run a test and track results
# @param $1 Test name / Название теста
# @param $2 Test script / Скрипт теста
# @return 0 if test passed, 1 if failed
run_test() {
    local test_name="$1"
    local test_script="$2"

    ((++total_tests))
    echo -e "${YELLOW}▶ Running test:${NC} $test_name"
    echo "----------------------------------------"

    if bash "${test_script}"; then
        echo -e "${GREEN}✓ $test_name: PASSED${NC}"
        ((++passed_tests))
        echo
        return 0
    else
        echo -e "${RED}✗ $test_name: FAILED${NC}"
        ((++failed_tests))
        echo
        return 1
    fi
}

# Запуск тестов каталога
# @description Run all tests from a directory (skips root tests unless allowed)
# @param $1 Directory / Каталог
# @param $2 Label / Метка
run_test_dir() {
    local dir="$1"
    local label="$2"

    [[ -d "${dir}" ]] || return 0

    echo -e "${BLUE}${label}:${NC}"
    local test_file test_name
    for test_file in "${dir}"/*.sh; do
        [[ -f "${test_file}" ]] || continue
        test_name=$(basename "${test_file}" .sh)
        if is_root_test "${test_file}"; then
            if [[ "${with_root}" -eq 1 ]] && [[ "${EUID}" -eq 0 ]]; then
                run_test "${label}: ${test_name}" "${test_file}"
            elif [[ "${with_root}" -eq 1 ]]; then
                skip_test "${label}: ${test_name}" "requires root / требует root (EUID != 0)"
            else
                skip_test "${label}: ${test_name}" "destructive/root test, use --with-root / деструктивный тест, нужен --with-root"
            fi
        else
            run_test "${label}: ${test_name}" "${test_file}"
        fi
    done
}

# Основная функция тестирования
main() {
    print_header "BS Framework Comprehensive Test Suite"
    print_header "Комплексный набор тестов фреймворка BS"

    echo -e "${YELLOW}Starting test execution...${NC}"
    echo -e "${YELLOW}Запуск выполнения тестов...${NC}"
    echo

    run_test_dir "unit" "Unit Tests / Модульные тесты"
    run_test_dir "integration" "Integration Tests / Интеграционные тесты"
    run_test_dir "data" "Data Tests / Тесты данных"
    run_test_dir "frameworks" "Frameworks Tests / Тесты фреймворков"
    run_test_dir "network" "Network Tests / Сетевые тесты"
    run_test_dir "status" "Status Tests / Тесты статуса"
    run_test_dir "audit" "Audit Tests / Тесты аудита"
    run_test_dir "demos" "Demo Tests / Демонстрационные тесты"

    # Сводка результатов
    print_header "TEST SUMMARY / СВОДКА ТЕСТОВ"

    echo -e "${BLUE}Total tests / Всего тестов:${NC} $total_tests"
    echo -e "${GREEN}Passed / Пройдено:${NC} $passed_tests"
    echo -e "${RED}Failed / Провалено:${NC} $failed_tests"
    echo -e "${YELLOW}Skipped / Пропущено:${NC} $skipped_tests"
    echo

    if [[ $failed_tests -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        echo -e "${GREEN}🎉 Все тесты пройдены!${NC}"
        if [[ $skipped_tests -gt 0 ]]; then
            echo -e "${YELLOW}Note: ${skipped_tests} test(s) skipped (see above) / пропущено тестов: ${skipped_tests}${NC}"
        fi
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
