#!/usr/bin/env bs
# tests/unit/testloaderunit.sh — Unit tests for bootstrap/loader module
# tests/unit/testloaderunit.sh — Модульные тесты для загрузчика bootstrap/loader
#
# Этот файл содержит unit тесты для загрузчика модулей.
# This file contains unit tests for the module loader.

set -euo pipefail

# Подключаем тестовый фреймворк (пути от расположения скрипта)
# Source test framework (paths relative to the script location)
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Подключаем bootstrap BS (ядро уже загружено через loader)
# Source BS bootstrap (core is already loaded via the loader)
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

# lib-модули подключают core через BS_HOME (pre-existing расхождение BS_ROOT/BS_HOME)
# lib modules source core via BS_HOME (pre-existing BS_ROOT/BS_HOME mismatch)
export BS_HOME="${BS_PROJECT_ROOT}"

# Главная функция тестов
main() {
    print_header "Loader Unit Tests / Модульные тесты загрузчика"
    
    testframework::init
    
    # Тест 1: Ядро загружено bootstrap'ом
    testframework::section "Core Loaded / Ядро загружено"
    testframework::assert_true "${BS_LOADED_MODULES[core/const]:-}" "core/const marked as loaded"
    testframework::assert_true "${BS_LOADED_MODULES[core/logger]:-}" "core/logger marked as loaded"
    testframework::assert_true "${BS_LOADED_MODULES[core/errorhandler]:-}" "core/errorhandler marked as loaded"
    
    # Тест 2: Загрузка существующего модуля
    testframework::section "Load Existing Module / Загрузка существующего модуля"
    testframework::assert_command 'load "lib/system/platformcheck"' "Load lib/system/platformcheck"
    testframework::assert_true "${BS_LOADED_MODULES[lib/system/platformcheck]:-}" "Module marked as loaded"
    
    # Тест 3: Повторная загрузка не грузит дважды
    testframework::section "Duplicate Load / Повторная загрузка"
    testframework::assert_command 'load "lib/system/platformcheck"' "Repeated load returns success"
    testframework::assert_equal "1" "${BS_LOADED_MODULES[lib/system/platformcheck]}" "Module still loaded once"
    
    # Тест 4: Загрузка несуществующего модуля
    testframework::section "Load Missing Module / Загрузка несуществующего модуля"
    
    local rc=0
    utils::quiet_err load "lib/nonexistent/module" || rc=$?
    testframework::assert_true "$rc -ne 0" "Missing module load fails"
    
    if [[ -z "${BS_LOADED_MODULES[lib/nonexistent/module]:-}" ]]; then
        testframework::assert_true "true" "Missing module not marked as loaded"
    else
        testframework::assert_true "false" "Missing module not marked as loaded"
    fi
    testframework::assert_true "${#BS_LOAD_STACK[@]} -eq 0" "Load stack clean after failure"
    
    # Тест 5: Повторная попытка после ошибки — без ложного circular dependency
    testframework::section "Retry After Failure / Повтор после ошибки"
    
    local err_out
    err_out=$(load "lib/nonexistent/module" 2>&1 || true)
    if echo "${err_out}" | grep -qi "circular"; then
        testframework::assert_true "false" "No false circular dependency on retry"
    else
        testframework::assert_true "true" "No false circular dependency on retry"
    fi
    
    rc=0
    utils::quiet_err load "lib/nonexistent/module" || rc=$?
    testframework::assert_true "$rc -ne 0" "Retry still fails with error"
    
    # Вывод сводки
    testframework::summary
}

# Запуск тестов
main "$@"
