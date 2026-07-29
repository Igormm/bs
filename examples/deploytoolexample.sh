#!/usr/bin/env bs
# examples/deploytoolexample.sh — Mini deploy tool: args + io::streams combo
# examples/deploytoolexample.sh — Мини-утилита деплоя: связка args + io::streams
#
# Полноценный маленький инструмент: дерево параметров, флаги, авто-help,
# bash-completion и логирование секции деплоя в файл через save/restore FD.
# A complete little tool: parameter tree, flags, auto-help,
# bash completion and deploy-section logging to a file via FD save/restore.
#
# Попробуйте / Try it:
#   bs run examples/deploytoolexample.sh deploy --env production --dry-run
#   bs run examples/deploytoolexample.sh rollback --env staging
#   bs run examples/deploytoolexample.sh --help

# Запуск / Run:
#   bs run examples/deploytoolexample.sh [args]
#   ./examples/deploytoolexample.sh            # bs должен быть в PATH / bs must be in PATH

# Наши два модуля / Our two modules
load "core/args"
load "lib/io/streams"

# Шаг «деплоя» с прогрессом / A "deploy" step with progress
deploy_step() {
    local title="${1}"
    local duration="${2:-0.2}"

    io::streams::printn "  ${title} "
    local tick
    for tick in 1 2 3; do
        sleep "${duration}"
        io::streams::printn "."
    done
    io::streams::print " OK"
}

main() {
    # ==========================================
    # Дерево параметров и флаги
    # Parameter tree and flags
    # ==========================================
    args::level 1 deploy rollback status
    args::flag env value
    args::flag dry-run

    args::describe deploy "Deploy the application"
    args::describe rollback "Roll back the last release"
    args::describe status "Show environment status"
    args::flag_describe env "Target environment (default: staging)"
    args::flag_describe dry-run "Plan only, no changes"

    # Служебный флаг для установки completion / Utility flag for completion install
    #   source <(bs run examples/deploytoolexample.sh --emit-completion)
    if [[ "${1:-}" == "--emit-completion" ]]; then
        args::completion "$(basename "$0")"
        exit "${E_SUCCESS}"
    fi

    args::parse "$@" || exit "${E_INVALID}"
    [[ "${ARGS_HELP_REQUESTED}" == "1" ]] && exit "${E_SUCCESS}"

    # ==========================================
    # Выполнение команды
    # Command execution
    # ==========================================
    local action="${ARGS_PARAMS[0]:-status}"
    local env
    env="$(args::flag_get env || printf 'staging')"

    if [[ "${action}" == "status" ]]; then
        io::streams::printf '  %-12s %s\n' "environment" "${env}" "release" "v1.4.2" "health" "green"
        exit "${E_SUCCESS}"
    fi

    # Сухой прогон / Dry run
    if args::flag_get dry-run >/dev/null; then
        log::warn "DRY RUN: ${action} into ${env} — no changes will be made"
    fi

    # ==========================================
    # Фишка: вся секция деплоя пишется в лог-файл,
    # а терминал видит только итог (save/restore FD)
    # The trick: the whole deploy section goes to a log file,
    # the terminal only sees the summary (FD save/restore)
    # ==========================================
    local log_file
    log_file="$(mktemp --suffix=-${action}-${env}.log)"
    trap "rm -f -- '${log_file}'" EXIT

    local saved_fd=""
    io::streams::save 1 saved_fd
    io::streams::redirect_all "${log_file}"

    io::streams::print "=== ${action} into ${env} started at $(date +%T) ==="
    deploy_step "Resolving artifacts"
    deploy_step "Stopping old release"
    deploy_step "Applying new release"
    deploy_step "Health check"
    io::streams::print "=== ${action} finished at $(date +%T) ==="

    io::streams::restore "${saved_fd}" 1

    # На терминале — только итог / On the terminal — only the summary
    log::success "${action} into ${env} done, $(wc -l < "${log_file}") log lines captured"
    io::streams::print "Log file contents:"
    io::streams::read_all < "${log_file}"
}

main "$@"
