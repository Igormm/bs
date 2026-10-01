#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsystemdunit.sh — Unit tests for lib/system/systemd
# tests/unit/testsystemdunit.sh — Модульные тесты для lib/system/systemd
#
# Тесты на временном каталоге юнитов (BS_SYSTEMD_UNIT_DIR): путь, запись,
# наличие, чтение ExecStart. Команды systemctl не трогаем.
# Tests in a temporary unit dir (BS_SYSTEMD_UNIT_DIR): path, write,
# existence, ExecStart reading. systemctl commands are not touched.

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
load "lib/system/systemd"

# Главная функция тестов
main() {
    print_header "Systemd Unit Tests / Модульные тесты systemd"

    testframework::init

    local tmp="${TMPDIR:-/tmp}/systemd_test_$$"
    mkdir -p "${tmp}"
    export BS_SYSTEMD_UNIT_DIR="${tmp}"

    testframework::section "unit_path / путь к юниту"
    testframework::assert_equal "${tmp}/demo.service" "$(systemd::unit_path demo)" "path format / формат пути"

    testframework::section "unit_write + unit_exists + unit_execstart / запись, наличие, ExecStart"
    local rc=0
    systemd::unit_write demo $'[Unit]\nDescription=opencode server for demo\n\n[Service]\nExecStart=/usr/bin/opencode serve --port 4096\n' 2>/dev/null || rc=$?
    testframework::assert_equal "0" "${rc}" "unit written / юнит записан"
    local exists=1
    systemd::unit_exists demo && exists=0
    testframework::assert_equal "0" "${exists}" "unit exists / юнит существует"
    testframework::assert_equal "/usr/bin/opencode serve --port 4096" "$(systemd::unit_execstart demo)" "ExecStart extracted / ExecStart извлечён"
    exists=0
    systemd::unit_exists no_such_unit_xyz && exists=1
    testframework::assert_equal "0" "${exists}" "unknown unit absent / несуществующего юнита нет"

    rm -rf "${tmp}"
    testframework::summary
}

# Запуск тестов
main "$@"