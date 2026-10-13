#!/usr/bin/env bs
# shellcheck shell=bash
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

# Один номер на весь репозиторий / One number for the whole repository
test_single_source() {
    local tmp top
    tmp="$(mktemp -d)"

    # Версия другого каталога читается, а не исполняется
    # The version of another directory is read, not executed
    mkdir -p "${tmp}/core"
    printf 'touch "%s/executed"\nexport BS_VERSION="9.8.7"\n' "${tmp}" > "${tmp}/core/version.sh"
    testframework::assert_equal "9.8.7" "$(bs::version::of "${tmp}")" "bs::version::of reads another directory"
    testframework::assert_command "test ! -e '${tmp}/executed'" "bs::version::of runs no code from that directory"
    testframework::assert_equal "" "$(bs::version::of "${tmp}/missing")" "bs::version::of of a missing directory is empty"
    testframework::assert_equal "${BS_VERSION}" "$(bs::version::of "${BS_PROJECT_ROOT}")" "bs::version::of the repository equals BS_VERSION"
    rm -rf "${tmp}"

    # const.sh не держит своего номера, CHANGELOG начинается с текущей версии
    # const.sh has no number of its own; the CHANGELOG starts with the current version
    testframework::assert_false "grep -qE 'BS_VERSION=\"[0-9]' '${BS_PROJECT_ROOT}/core/const.sh'" "core/const.sh has no version literal"
    top="$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' "${BS_PROJECT_ROOT}/CHANGELOG.md" | head -n 1)"
    testframework::assert_equal "${BS_VERSION}" "${top}" "the top CHANGELOG section is the current version"
    testframework::assert_equal "$(bash "${BS_PROJECT_ROOT}/bs" version)" "$(bash "${BS_PROJECT_ROOT}/bs" version --full | head -n 1)" "bs version --full starts with the plain bs version line"
}

# Главная функция тестов
main() {
    print_header "Version Unit Tests / Модульные тесты версий"
    
    testframework::init

    testframework::section "Single source / Один источник"
    test_single_source
    
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
    
    rc=0
    bs::version::compare "1.2.3rc1" "1.2.9" || rc=$?
    testframework::assert_equal "2" "$rc" "1.2.3rc1 < 1.2.9 (suffix is not digits)"

    rc=0
    bs::version::compare "0.8.0-rc1" "0.8.0" || rc=$?
    testframework::assert_equal "0" "$rc" "0.8.0-rc1 == 0.8.0 (suffix ignored)"

    rc=0
    bs::version::compare "v0.10.0" "0.9.0" || rc=$?
    testframework::assert_equal "1" "$rc" "v-prefix: v0.10.0 > 0.9.0"

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
