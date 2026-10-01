#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testuserunit.sh — Unit tests for lib/system/user
# tests/unit/testuserunit.sh — Модульные тесты для lib/system/user
#
# Тесты: user::exists, запись лимитов в временный каталог (BS_LIMITS_DIR),
# запись sudoers с visudo -c (BS_SUDOERS_DIR) — контракт: при успехе файл
# остаётся, при неудаче проверки удаляется.
# Tests: user::exists, limits written to a temp dir (BS_LIMITS_DIR),
# sudoers with visudo -c (BS_SUDOERS_DIR) — contract: on success the file
# stays, on verification failure it is removed.

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
load "lib/system/user"

# Главная функция тестов
main() {
    print_header "User Unit Tests / Модульные тесты user"

    testframework::init

    local tmp="${TMPDIR:-/tmp}/user_test_$$"
    mkdir -p "${tmp}"
    export BS_LIMITS_DIR="${tmp}"
    export BS_SUDOERS_DIR="${tmp}"

    testframework::section "user::exists / существование пользователя"
    local exists=1
    user::exists "$(id -un)" && exists=0
    testframework::assert_equal "0" "${exists}" "current user exists / текущий пользователь существует"
    exists=0
    user::exists no_such_user_xyz_123 && exists=1
    testframework::assert_equal "0" "${exists}" "unknown user absent / несуществующего пользователя нет"

    testframework::section "write_limits / лимиты ресурсов"
    local path
    path="$(user::write_limits demo 128 4096)"
    testframework::assert_true "-f '${path}'" "limits file written / файл лимитов записан"
    testframework::assert_true "'$(grep -c 'demo hard nproc 128' "${path}")' != '0'" "nproc line present / строка nproc на месте"
    testframework::assert_true "'$(grep -c 'demo hard core 0' "${path}")' != '0'" "core=0 line present / строка core=0 на месте"

    testframework::section "write_sudoers / sudoers с проверкой"
    local rc=0
    user::write_sudoers demo "systemctl start demo.service" >/dev/null 2>&1 || rc=$?
    if (( rc == 0 )); then
        testframework::assert_true "-f '${tmp}/demo'" "sudoers written and verified / sudoers записан и проверен"
    else
        testframework::assert_false "-f '${tmp}/demo'" "sudoers reverted on visudo failure / sudoers откачен при неудаче visudo"
    fi

    rm -rf "${tmp}"
    testframework::summary
}

# Запуск тестов
main "$@"