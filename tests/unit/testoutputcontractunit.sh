#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testoutputcontractunit.sh — Unit tests for lib/ui/output_contract
# tests/unit/testoutputcontractunit.sh — Модульные тесты для lib/ui/output_contract
#
# Тесты: каталог не пуст и формат записей корректен (id:title:source:demo),
# list печатает все id, check находит все демо-скрипты, demo с неизвестным
# id возвращает 1.
# Tests: catalog is non-empty with well-formed entries (id:title:source:demo),
# list prints every id, check finds all demo scripts, demo with an unknown
# id returns 1.

set -euo pipefail

# Подключаем тестовый фреймворк (пути от расположения скрипта)
# Source test framework (paths relative to the script location)
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Подключаем bootstrap BS (модуль загружается через loader)
# Source BS bootstrap (the module is loaded via the loader)
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
load "lib/ui/output_contract"

# Главная функция тестов
main() {
    print_header "Output Contract Unit Tests / Модульные тесты контракта вывода"

    testframework::init

    testframework::section "Catalog shape / Форма каталога"
    testframework::assert_true "'${#OUTPUT_CONTRACT_UNITS[@]}' -ge 1" "catalog is not empty / каталог не пуст"
    local entry bad=0
    for entry in "${OUTPUT_CONTRACT_UNITS[@]}"; do
        if [[ "${entry}" != *:*:*:* ]]; then
            bad=1
        fi
    done
    testframework::assert_true "'${bad}' = '0'" "every entry is id:title:source:demo / каждая запись корректна"

    testframework::section "list prints all ids / list печатает все id"
    local out
    out="$(output_contract::list)"
    local missing=0
    for entry in "${OUTPUT_CONTRACT_UNITS[@]}"; do
        if [[ "${out}" != *"${entry%%:*}"* ]]; then
            missing=1
        fi
    done
    testframework::assert_true "'${missing}' = '0'" "list contains every unit id / list содержит все id"

    testframework::section "check finds all demos / check находит все демо"
    local rc=0
    output_contract::check >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "all demo scripts exist / все демо-скрипты на месте"

    testframework::section "demo with an unknown id / demo с неизвестным id"
    rc=0
    output_contract::demo "no_such_unit" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "1" "${rc}" "unknown unit returns 1 / неизвестная единица возвращает 1"

    testframework::summary
}

# Запуск тестов
main "$@"