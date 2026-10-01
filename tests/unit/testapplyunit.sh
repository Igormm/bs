#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testapplyunit.sh — Unit tests for lib/system/apply
# tests/unit/testapplyunit.sh — Модульные тесты для lib/system/apply
#
# Тесты: apply::run возвращает код команды, apply::check_tools находит
# отсутствующие утилиты.
# Tests: apply::run returns the command's exit code, apply::check_tools
# detects missing tools.

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
load "lib/system/apply"

# Главная функция тестов
main() {
    print_header "Apply Unit Tests / Модульные тесты apply"

    testframework::init

    testframework::section "apply::run / выполнение шага"
    local rc=0
    apply::run "true command" true 2>/dev/null || rc=$?
    testframework::assert_equal "0" "${rc}" "successful step returns 0 / успешный шаг возвращает 0"

    rc=0
    apply::run "false command" false 2>/dev/null || rc=$?
    testframework::assert_equal "1" "${rc}" "failed step returns 1 / неудачный шаг возвращает 1"

    testframework::section "apply::check_tools / проверка утилит"
    rc=0
    apply::check_tools bash 2>/dev/null || rc=$?
    testframework::assert_equal "0" "${rc}" "present tools pass / существующие утилиты проходят"

    rc=0
    apply::check_tools bash no_such_tool_xyz_123 2>/dev/null || rc=$?
    testframework::assert_equal "1" "${rc}" "missing tool fails / отсутствующая утилита не проходит"

    testframework::summary
}

# Запуск тестов
main "$@"