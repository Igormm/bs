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

    local -r name="${ARGS_FLAGS["name"]:-world}"
    local msg
    case "${ARGS_PARAMS[0]}" in
        hello)   msg="Hello, ${name}!" ;;
        goodbye) msg="Goodbye, ${name}!" ;;
    esac
    args::flag_is_set loud && msg="${msg^^}"
    io::streams::print "${msg}"
}

main "$@"