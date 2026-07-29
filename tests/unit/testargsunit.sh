#!/usr/bin/env bs
# tests/unit/testargsunit.sh — Unit tests for args module
# tests/unit/testargsunit.sh — Модульные тесты для модуля параметров
#
# Этот файл содержит unit тесты для модуля args (core/args.sh).
# This file contains unit tests for the args module (core/args.sh).

set -euo pipefail

# Подключаем тестовый фреймворк (пути от расположения скрипта)
# Source test framework (paths relative to the script location)
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Подключаем bootstrap BS (ядро загружается через loader)
# Source BS bootstrap (core is loaded via the loader)
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

# Главная функция тестов
main() {
    print_header "Args Module Unit Tests"
    print_header "Модульные тесты модуля параметров"

    testframework::init

    # Тест 1: Инициализация модуля
    testframework::section "Module Initialization / Инициализация модуля"
    load "core/args"
    testframework::assert_true "${ARGS_LOADED:-}" "Module initialized"
    testframework::assert_equal "1.0.0" "${ARGS_VERSION}" "Version correct"

    # Тест 2: Линейное объявление (args::define)
    testframework::section "Linear Declaration / Линейное объявление"

    args::reset
    args::define first middle last

    args::parse first middle last
    testframework::assert_equal "3" "${#ARGS_PARAMS[@]}" "All three params parsed"
    testframework::assert_equal "first" "$(args::get 1)" "Param at position 1"
    testframework::assert_equal "middle" "$(args::get 2)" "Param at position 2"
    testframework::assert_equal "last" "$(args::get 3)" "Param at position 3"

    # Частичный набор допустим / Partial set is allowed
    args::parse first
    testframework::assert_equal "1" "${#ARGS_PARAMS[@]}" "Partial params allowed"

    # Тест 3: Неизвестный параметр
    testframework::section "Unknown Parameter / Неизвестный параметр"

    local rc=0
    args::parse first unknown_param 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "Unknown param returns E_INVALID"

    local err_msg
    err_msg="$(args::parse first unknown_param 2>&1 >/dev/null || true)"
    testframework::assert_true "\$err_msg =~ unknown" "Error mentions unknown parameter"
    testframework::assert_true "\$err_msg =~ Usage" "Help is printed on error"

    # Тест 4: Параметр не на том уровне
    testframework::section "Wrong Level / Параметр не на том уровне"

    rc=0
    args::parse middle 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "Wrong level returns E_INVALID"

    err_msg="$(args::parse middle 2>&1 >/dev/null || true)"
    testframework::assert_true "\$err_msg =~ 'belongs to level 2'" "Error names the right level"

    # Тест 5: Слишком много параметров
    testframework::section "Too Many Parameters / Слишком много параметров"

    rc=0
    args::parse first middle last extra 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "Extra param returns E_INVALID"

    err_msg="$(args::parse first middle last extra 2>&1 >/dev/null || true)"
    testframework::assert_true "\$err_msg =~ 'too many'" "Error mentions too many params"

    # Тест 6: Ветвление дерева (args::level)
    testframework::section "Tree Branching / Ветвление дерева"

    args::reset
    args::level 1 start stop status
    args::level 2 now later

    args::parse stop later
    testframework::assert_equal "stop" "$(args::get 1)" "Alternative branch parsed"
    testframework::assert_equal "later" "$(args::get 2)" "Second level branch parsed"

    # Альтернатива с чужого уровня отклоняется / Alternative from another level rejected
    rc=0
    args::parse now 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "Level-2 param at level 1 rejected"

    # Дубликаты не задваиваются / Duplicates are not duplicated
    args::level 1 start
    testframework::assert_equal "start stop status" "${__ARGS_TREE[1]}" "No duplicates in tree"

    # Тест 7: Help
    testframework::section "Help Generation / Генерация help"

    args::reset
    args::define deploy rollback
    args::describe deploy "Deploy the application"

    local help_out
    help_out="$(args::help "myscript.sh")"
    testframework::assert_true "\$help_out == *'Usage: myscript.sh [deploy] [rollback]'*" "Usage line generated"
    testframework::assert_true "\$help_out =~ 'Deploy the application'" "Description included"

    # -h/--help: код 0, флаг выставлен / -h/--help: code 0, flag set
    args::parse --help >/dev/null
    testframework::assert_equal "1" "${ARGS_HELP_REQUESTED}" "Help flag set on --help"
    testframework::assert_equal "0" "${#ARGS_PARAMS[@]}" "No params on help request"

    # Тест 8: args::get за пределами
    testframework::section "args::get Out of Range / args::get за пределами"

    args::reset
    args::define one
    args::parse one

    local get_rc=0
    args::get 5 >/dev/null || get_rc=$?
    testframework::assert_equal "${E_ERROR}" "${get_rc}" "get beyond range fails"
    testframework::assert_false "args::get 0" "get rejects zero position"

    # Тест 9: Сброс дерева
    testframework::section "Tree Reset / Сброс дерева"

    args::reset
    args::define alpha
    rc=0
    args::parse one 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "Old params rejected after reset"
    args::parse alpha
    testframework::assert_equal "alpha" "$(args::get 1)" "New tree works after reset"

    # Тест 10: Обработка ошибок объявления
    testframework::section "Declaration Errors / Ошибки объявления"

    testframework::assert_false "args::define" "define requires names"
    testframework::assert_false "args::level 0 foo" "level rejects zero"
    testframework::assert_false "args::level abc foo" "level rejects non-numeric"
    testframework::assert_false "args::level 1" "level requires names"
    testframework::assert_false "args::describe ''" "describe requires a name"

    # Парсинг без объявленного дерева / Parse without a declared tree
    args::reset
    rc=0
    args::parse anything 2>/dev/null || rc=$?
    testframework::assert_equal "${E_ERROR}" "${rc}" "Parse without tree returns E_ERROR"

    # Тест 11: Флаги --key value
    testframework::section "Flags / Флаги"

    args::reset
    args::define deploy
    args::flag verbose
    args::flag output value

    # bool-флаг и флаг со значением / bool flag and value flag
    args::parse deploy --verbose --output report.txt
    testframework::assert_equal "1" "${ARGS_FLAGS[verbose]}" "Bool flag set"
    testframework::assert_equal "report.txt" "$(args::flag_get output)" "Value flag parsed"
    testframework::assert_equal "deploy" "$(args::get 1)" "Positional intact with flags"

    # Форма --key=value / --key=value form
    args::parse deploy --output=report2.txt
    testframework::assert_equal "report2.txt" "$(args::flag_get output)" "Inline flag value parsed"

    # Флаги не занимают позиционные уровни / Flags do not occupy levels
    args::parse --verbose deploy
    testframework::assert_equal "deploy" "$(args::get 1)" "Flag before positional does not shift level"

    # Неизвестный флаг / Unknown flag
    rc=0
    args::parse deploy --bogus 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "Unknown flag returns E_INVALID"

    # Флаг со значением без значения / Value flag without value
    rc=0
    args::parse deploy --output 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "Missing flag value returns E_INVALID"

    # bool-флаг со значением / Bool flag given a value
    rc=0
    args::parse deploy --verbose=yes 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "Bool flag with value returns E_INVALID"

    # Флаг не задан / Flag not set
    args::parse deploy
    testframework::assert_false "args::flag_get output" "flag_get fails when flag not set"

    # Префикс -- в объявлении и запросе допустим / -- prefix allowed in declaration and query
    args::reset
    args::flag --force
    args::parse --force
    testframework::assert_equal "1" "$(args::flag_get --force)" "Flag works with -- prefix"

    # Только флаги, без дерева / Flags only, no tree
    args::reset
    args::flag verbose
    args::parse --verbose
    testframework::assert_equal "1" "${ARGS_FLAGS[verbose]}" "Flags-only declaration parses"
    rc=0
    args::parse anything 2>/dev/null || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "Positional rejected with flags-only tree"

    # Тест 12: Help с флагами
    testframework::section "Help with Flags / Help с флагами"

    args::reset
    args::define deploy
    args::flag output value
    args::flag_describe output "Write the report to this file"

    help_out="$(args::help "myscript.sh")"
    testframework::assert_true "\$help_out == *'[flags] [deploy]'*" "Usage line includes flags"
    testframework::assert_true "\$help_out == *'--output <value>'*" "Flag section shows value hint"
    testframework::assert_true "\$help_out == *'Write the report to this file'*" "Flag description included"

    # Тест 13: Bash completion
    testframework::section "Bash Completion / Автодополнение Bash"

    args::reset
    args::level 1 deploy rollback
    args::level 2 now later
    args::flag verbose
    args::flag env value

    local comp_out
    comp_out="$(args::completion "deploy.sh")"
    testframework::assert_true "\$comp_out == *'complete -F _deploy_sh_completion deploy.sh'*" "complete command generated"
    testframework::assert_true "\$comp_out == *'1) choices=\"deploy rollback\" ;;'*" "Level 1 choices embedded"
    testframework::assert_true "\$comp_out == *'2) choices=\"now later\" ;;'*" "Level 2 choices embedded"
    testframework::assert_true "\$comp_out == *'--env --verbose'*" "Flags embedded"

    # Сгенерированная функция реально работает / Generated function actually works
    local comp_file
    comp_file="$(mktemp)"
    args::completion "deploy.sh" > "${comp_file}"
    (
        source "${comp_file}"
        COMP_WORDS=(deploy.sh "")
        COMP_CWORD=1
        _deploy_sh_completion
        printf '%s\n' "${COMPREPLY[*]}"
    ) > /tmp/args_comp_result.$$
    testframework::assert_true "\"$(cat /tmp/args_comp_result.$$)\" == *'deploy rollback'*" "Completion offers level 1"
    rm -f "${comp_file}" /tmp/args_comp_result.$$

    # completion без объявлений / completion without declarations
    args::reset
    testframework::assert_false "args::completion x" "Completion fails with empty tree"

    # Вывод сводки
    testframework::summary
}

# Запуск тестов
main "$@"
