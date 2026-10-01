#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testwizardunit.sh — Unit tests for lib/ui/wizard engine
# tests/unit/testwizardunit.sh — Модульные тесты движка визарда lib/ui/wizard
#
# Тесты неинтерактивных частей: gen_pass (набор символов, длина), ввод с
# пайпа (значение/дефолт/отмена), меню (цифры/отмена), чекбоксы, y/n,
# пароль с подтверждением.
# Tests of the non-interactive parts: gen_pass (charset, length), input via
# pipe (value/default/cancel), menu (digits/cancel), checkboxes, y/n,
# password with confirmation.

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
load "lib/ui/wizard"

# Обёртки: клавиши из пайпа, рамки — в /dev/null
# Wrappers: keys from the pipe, frames — into /dev/null
wiz_test::input() {
    local result=""
    wizard::ask_input result "Prompt" "$1" "" >/dev/null 2>&1
    printf '%s' "${result}"
}

wiz_test::menu() {
    local pick=99
    wizard::menu pick "Title" "" "A" "B" "C" >/dev/null 2>&1
    printf '%s' "${pick}"
}

wiz_test::multi() {
    local pick="q"
    wizard::multi_menu pick "Title" "" "X" "Y" >/dev/null 2>&1
    printf '%s' "${pick}"
}

wiz_test::yn() {
    local ans="q"
    wizard::yn ans "Question" "" >/dev/null 2>&1
    printf '%s' "${ans}"
}

wiz_test::pass() {
    local result=""
    wizard::ask_pass result "" >/dev/null 2>&1
    printf '%s' "${result}"
}

# Главная функция тестов
main() {
    print_header "Wizard Unit Tests / Модульные тесты движка визарда"

    testframework::init

    testframework::section "gen_pass / генерация пароля"
    local pass
    pass="$(wizard::gen_pass)"
    testframework::assert_true "'${pass}' =~ ^[A-Za-z0-9_-]+$" "charset [A-Za-z0-9_-]"
    testframework::assert_true "'${#pass}' -ge 18 && '${#pass}' -le 24" "length 18..24"

    testframework::section "ask_input / текстовый ввод"
    testframework::assert_equal "abc" "$(printf 'abc\n' | wiz_test::input 'def')" "typed value wins / введённое значение"
    testframework::assert_equal "def" "$(printf '\n' | wiz_test::input 'def')" "empty input keeps default / пустой ввод — дефолт"
    testframework::assert_equal "q" "$(printf 'q\n' | wiz_test::input 'def')" "q cancels / q отменяет"

    testframework::section "menu / меню"
    testframework::assert_equal "2" "$(printf '3\n' | wiz_test::menu)" "digit selects item / цифра выбирает пункт"
    testframework::assert_equal "99" "$(printf 'q\n' | wiz_test::menu)" "q cancels / q отменяет"

    testframework::section "multi_menu / чекбоксы"
    testframework::assert_equal "0" "$(printf ' \n' | wiz_test::multi)" "space checks the first item / space отмечает первый"

    testframework::section "yn / да-нет"
    testframework::assert_equal "y" "$(printf 'y\n' | wiz_test::yn)" "y answers yes / y — да"
    testframework::assert_equal "n" "$(printf '2\n' | wiz_test::yn)" "2 answers no / 2 — нет"

    testframework::section "ask_pass / пароль с подтверждением"
    testframework::assert_equal "p1" "$(printf 'p1\np1\n' | wiz_test::pass)" "matching passwords accepted / совпавшие пароли приняты"
    testframework::assert_equal "" "$(printf '\n' | wiz_test::pass)" "empty password = none / пустой пароль = без пароля"

    testframework::summary
}

# Запуск тестов
main "$@"