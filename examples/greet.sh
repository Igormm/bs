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
    args::level 1 hello goodbye
    args::describe hello "Greet a name"
    args::describe goodbye "Say goodbye to a name"
    args::flag name value world
    args::flag loud
    args::flag_describe name "Who to greet"
    args::flag_describe loud "Uppercase the greeting"
    args::required 1
    args::require "$@"

    # Читаем разобранные аргументы понятными функциями / Read the parsed arguments with readable functions:
    #   args::param 1        — первое слово после имени скрипта (hello или goodbye) / the first word after the script name
    #   args::flag_get name  — значение --name; без него — дефолт world из args::flag / the --name value, or the default world
    local -r command="$(args::param 1)"
    local -r name="$(args::flag_get name)"
    local msg
    case "${command}" in
        hello)   msg="Hello, ${name}!" ;;
        goodbye) msg="Goodbye, ${name}!" ;;
    esac
    args::flag_is_set loud && msg="${msg^^}"
    io::streams::print "${msg}"
}

main "$@"