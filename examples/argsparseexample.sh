#!/usr/bin/env bs
# examples/argsparseexample.sh — Parameter tree demo for args module
# examples/argsparseexample.sh — Демонстрация дерева параметров модуля args
#
# Этот скрипт показывает, как объявить допустимые параметры один раз
# и получить валидацию + help автоматически.
# This script shows how to declare allowed parameters once
# and get validation + help automatically.
#
# Попробуйте / Try it:
#   bs run examples/argsparseexample.sh deploy now
#   bs run examples/argsparseexample.sh now          # ошибка уровня / level error
#   bs run examples/argsparseexample.sh fly          # неизвестный параметр / unknown
#   bs run examples/argsparseexample.sh --help

# Запуск / Run:
#   bs run examples/argsparseexample.sh [args]
#   ./examples/argsparseexample.sh            # bs должен быть в PATH / bs must be in PATH

# Подключаем модуль параметров / Load the args module
load "core/args"

main() {
    # ==========================================
    # 1. Объявляем дерево параметров один раз
    #    Declare the parameter tree once
    # ==========================================

    # Уровень 1: что делаем; уровень 2: когда
    # Level 1: what to do; level 2: when
    args::level 1 deploy rollback status
    args::level 2 now later

    # Описания попадут в help / Descriptions go into the help
    args::describe deploy "Deploy the application to servers"
    args::describe rollback "Roll back to the previous release"
    args::describe status "Show deployment status"
    args::describe now "Execute immediately"
    args::describe later "Schedule for the maintenance window"

    # Флаги не занимают позиционные уровни
    # Flags do not occupy positional levels
    args::flag env value           # --env production / --env=production
    args::flag dry-run             # --dry-run (без значения / no value)
    args::flag_describe env "Target environment (staging, production)"
    args::flag_describe dry-run "Print the plan without executing"

    # ==========================================
    # 2. Валидируем входные параметры
    #    Validate the input parameters
    # ==========================================

    # Скрытый служебный флаг: печать completion для source
    # Hidden utility flag: print completion for sourcing
    # Установка (одна строка в ~/.bashrc) / Install (one line in ~/.bashrc):
    #   source <(bs run examples/argsparseexample.sh --emit-completion)
    if [[ "${1:-}" == "--emit-completion" ]]; then
        args::completion "$(basename "$0")"
        exit "${E_SUCCESS}"
    fi

    # При ошибке parse сам печатает причину и help в stderr
    # On error parse prints the reason and help to stderr itself
    if ! args::parse "$@"; then
        exit "${E_INVALID}"
    fi

    # -h/--help уже обработан: help напечатан, просто выходим
    # -h/--help is already handled: help was printed, just exit
    if [[ "${ARGS_HELP_REQUESTED}" == "1" ]]; then
        exit "${E_SUCCESS}"
    fi

    # ==========================================
    # 3. Работаем с провалидированными параметрами
    #    Work with the validated parameters
    # ==========================================

    local action="${ARGS_PARAMS[0]:-status}"   # действие по умолчанию / default action
    local timing="${ARGS_PARAMS[1]:-now}"      # время по умолчанию / default timing
    local env
    env="$(args::flag_get env || printf 'staging')"   # окружение по умолчанию / default env

    log::info "Action: ${action}, timing: ${timing}, env: ${env}"
    if args::flag_get dry-run >/dev/null; then
        log::warn "DRY RUN: no changes will be made"
    fi
    case "${action}" in
        deploy)   log::success "Deploying to ${env} (${timing})..." ;;
        rollback) log::warn "Rolling back ${env} (${timing})..." ;;
        status)   log::info "Everything in ${env} is running fine" ;;
    esac

    # ==========================================
    # 4. Bash completion из того же дерева
    #    Bash completion from the same tree
    # ==========================================
    log::header "Bash completion / Автодополнение Bash"

    # BASH_SOURCE[0]: под 'bs run' $0 — это "bash", а не путь скрипта
    # BASH_SOURCE[0]: under 'bs run' $0 is "bash", not the script path
    log::info "Install: source <(bs run ${BASH_SOURCE[0]} --emit-completion)"
    # Показываем первые строки сгенерированного кода
    # sed читает весь поток до EOF — в отличие от head не закрывает pipe
    # раньше времени и не ловит SIGPIPE под pipefail
    # Show the first lines of the generated code
    # sed reads the whole stream until EOF — unlike head it does not close
    # the pipe early and does not hit SIGPIPE under pipefail
    args::completion "argsparseexample.sh" | sed -n '1,5p'

    # ==========================================
    # 5. Линейный вариант: args::define
    #    Linear variant: args::define
    # ==========================================
    log::header "Linear chain demo / Демонстрация линейной цепочки"

    # Эквивалент parameters("first", "middle", "last"):
    # цепочка first → middle → last по уровням 1-2-3
    # Equivalent of parameters("first", "middle", "last"):
    # the chain first → middle → last at levels 1-2-3
    args::reset
    args::define first middle last
    args::describe first "First stage"
    args::describe middle "Middle stage"
    args::describe last "Last stage"
    args::help "pipeline.sh"

    log::success "Args demo finished / Демонстрация параметров завершена"
}

main "$@"
