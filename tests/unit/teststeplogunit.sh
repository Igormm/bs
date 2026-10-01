#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/teststeplogunit.sh — Unit tests for lib/ui/steplog module
# tests/unit/teststeplogunit.sh — Модульные тесты для модуля lib/ui/steplog
#
# Тесты: инициализация с писабельным файлом, fallback на непишемый файл
# (чужой root-файл в /tmp не должен ронять init), запись шагов и сброс.
# Tests: init with a writable file, fallback on an unwritable file (a
# foreign root-owned file in /tmp must not crash init), step recording
# and flush.

set -euo pipefail

# Подключаем тестовый фреймворк (пути от расположения скрипта)
# Source test framework (paths relative to the script location)
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Подключаем bootstrap BS (lib/ui/steplog загружается через loader)
# Source BS bootstrap (lib/ui/steplog is loaded via the loader)
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
load "lib/ui/steplog"

# Главная функция тестов
main() {
    print_header "Steplog Unit Tests / Модульные тесты steplog"

    testframework::init

    testframework::section "Init with a writable file / Инициализация с писабельным файлом"
    local logfile="${TMPDIR:-/tmp}/steplog_test.$$.log"
    rm -f "${logfile}"
    steplog::init "${logfile}" 0
    testframework::assert_true "-f ${logfile}" "log file created / файл журнала создан"
    testframework::assert_equal "${logfile}" "${STEPLOG_FILE}" "STEPLOG_FILE set / задан"

    testframework::section "Record and flush / Запись и сброс"
    steplog::step "useradd test"
    steplog::ok "user created"
    steplog::finish
    testframework::assert_true "'$(grep -c 'useradd test' "${logfile}" 2>/dev/null)' != '0'" "step line flushed / строка шага сброшена"
    testframework::assert_true "'$(grep -c 'user created' "${logfile}" 2>/dev/null)' != '0'" "ok line flushed / строка успеха сброшена"

    testframework::section "Fallback on an unwritable file / Запасной журнал при непишемом файле"
    local ro_file="/proc/steplog_forbidden.$$"
    local fallback
    fallback="$(steplog::init "${ro_file}" 0 >/dev/null 2>&1; printf '%s' "${STEPLOG_FILE}")"
    testframework::assert_false "test '${fallback}' = '${ro_file}'" "init falls back off an unwritable file / init уходит с непишемого файла"
    testframework::assert_true "-n '${fallback}'" "fallback path is set / запасной путь задан"

    rm -f "${logfile}" "${fallback}"

    testframework::summary
}

# Запуск тестов
main "$@"