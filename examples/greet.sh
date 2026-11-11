#!/usr/bin/env bs
# shellcheck shell=bash
# examples/greet.sh — short script with core/args (tree, flags, auto-help)
# examples/greet.sh — короткий скрипт с core/args (дерево, флаги, авто-help)

# Запуск / Run:
#   ./bs run examples/greet.sh hello --name Bob
#   ./bs run examples/greet.sh hello --name Bob --loud
#   ./bs run examples/greet.sh goodbye --name Alice
#   ./bs run examples/greet.sh --help

load "core/args"
load "lib/io/streams"

main() {
    # 1. Описываем, что скрипт принимает / Declare what the script accepts
    args::level 1 hello goodbye                 # первое слово: hello или goodbye
    args::describe hello "Greet a name"
    args::describe goodbye "Say goodbye to a name"
    args::flag name value world                 # --name ИМЯ, по умолчанию world
    args::flag loud                             # --loud, флаг без значения
    args::flag_describe name "Who to greet"
    args::flag_describe loud "Uppercase the greeting"
    args::required 1                            # без команды — ошибка и help

    # 2. Проверяем аргументы: ошибка или --help — выход сразу
    #    Validate arguments: an error or --help exits right here
    args::require "$@"

    # 3. Читаем значения по смыслу / Read the values by meaning
    local command name msg
    command="$(args::get 1)"                    # hello | goodbye
    name="$(args::flag_get name)"               # значение --name или дефолт world

    case "${command}" in
        hello)   msg="Hello, ${name}!" ;;
        goodbye) msg="Goodbye, ${name}!" ;;
    esac
    if args::flag_is_set loud; then
        msg="${msg^^}"
    fi
    io::streams::print "${msg}"
}

main "$@"
