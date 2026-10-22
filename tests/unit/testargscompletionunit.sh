#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testargscompletionunit.sh — args::completion for bash, zsh, fish and nushell
# tests/unit/testargscompletionunit.sh — args::completion для bash, zsh, fish и nushell
#
# One declaration of levels and flags, four generators. zsh is also loaded in a
# real zsh with compinit; fish and nushell are checked as text only (those
# shells are not run here).
# Одно объявление уровней и флагов, четыре генератора. zsh дополнительно
# загружается в настоящем zsh с compinit; fish и nushell проверяются как текст
# (эти оболочки здесь не запускаются).

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
load "core/args"

T=""

has() {
    if [[ "$1" == *"$2"* ]]; then testframework::assert_true "true" "$3" || true
    else testframework::assert_true "false" "$3" || true; printf '    not found / не найдено: %s\n' "$2"; fi
}

main() {
    print_header "args::completion shells / Автодополнение по оболочкам"

    testframework::init
    T="$(mktemp -d)"

    args::reset
    args::level 1 deploy rollback
    args::level 2 now later
    args::flag verbose
    args::flag port value "" number
    args::flag env value staging "enum:staging,prod"

    local out
    testframework::section "bash (default / по умолчанию)"
    out="$(args::completion deploy.sh)"
    has "${out}" 'complete -F _deploy_sh_completion "deploy.sh"' "bash is the default"
    out="$(BS_COMPLETION_SHELL=bash args::completion deploy.sh)"
    has "${out}" "1) choices=\"deploy rollback\" ;;" "BS_COMPLETION_SHELL=bash"

    testframework::section "zsh"
    out="$(args::completion deploy.sh zsh)"
    has "${out}" '#compdef deploy.sh' "zsh: #compdef header"
    has "${out}" "'--verbose'" "zsh: a bool flag"
    has "${out}" "'--env=:value:(staging prod)'" "zsh: an enum flag"
    has "${out}" "'--port=:value: '" "zsh: a value flag"
    has "${out}" "'1:argument 1:(deploy rollback)'" "zsh: level 1 choices"
    has "${out}" "'2:argument 2:(now later)'" "zsh: level 2 choices"
    has "${out}" 'compdef _deploy_sh_completion deploy.sh' "zsh: compdef"
    printf '%s\n' "${out}" > "${T}/_deploy.sh"
    if command -v zsh >/dev/null 2>&1; then
        testframework::assert_command "zsh -n '${T}/_deploy.sh'" "zsh: the output parses in zsh" || true
        testframework::assert_command "zsh -f -c 'autoload -Uz compinit; compinit -u -d ${T}/zcompdump; source ${T}/_deploy.sh; (( \${+_comps[deploy.sh]} ))'" "zsh: compdef registers the completion in a real zsh" || true
    else
        printf '  skip: zsh is not installed / не установлен\n'
    fi

    testframework::section "fish (text only / только текст)"
    out="$(args::completion deploy.sh fish)"
    has "${out}" "complete -c 'deploy.sh' -f" "fish: no file completion"
    has "${out}" "complete -c 'deploy.sh' -l verbose" "fish: a bool flag"
    has "${out}" "complete -c 'deploy.sh' -l port -r" "fish: a value flag"
    has "${out}" "complete -c 'deploy.sh' -l env -x -a 'staging prod'" "fish: an enum flag"
    has "${out}" "-n '__fish_is_nth_token 1' -a 'deploy rollback'" "fish: level 1 choices"

    testframework::section "nushell (text only / только текст)"
    out="$(args::completion deploy.sh nu)"
    has "${out}" 'extern "deploy.sh" [' "nu: extern block"
    has "${out}" '  --verbose' "nu: a bool flag"
    has "${out}" '  --port: string' "nu: a value flag"
    has "${out}" '  --env: string@"nu-complete deploy.sh --env"' "nu: an enum flag"
    has "${out}" 'def "nu-complete deploy.sh arg 1" [] { [ "deploy" "rollback" ] }' "nu: level 1 completer"
    has "${out}" 'arg2?: string@"nu-complete deploy.sh arg 2"' "nu: level 2 positional"
    out="$(args::completion deploy.sh nushell)"
    has "${out}" 'extern "deploy.sh" [' "nu: the synonym nushell"

    testframework::section "help and completions agree / help и дополнения согласованы"
    local help_out bash_out zsh_out fish_out nu_out flag value
    help_out="$(args::help deploy.sh)"
    bash_out="$(args::completion deploy.sh)"
    zsh_out="$(args::completion deploy.sh zsh)"
    fish_out="$(args::completion deploy.sh fish)"
    nu_out="$(args::completion deploy.sh nu)"
    for flag in verbose port env; do
        has "${help_out}" "--${flag}" "help: --${flag}"
        has "${bash_out}" "--${flag}" "bash: --${flag}"
        has "${zsh_out}" "--${flag}" "zsh: --${flag}"
        has "${fish_out}" "-l ${flag}" "fish: --${flag}"
        has "${nu_out}" "--${flag}" "nu: --${flag}"
    done
    for value in staging prod; do
        has "${help_out}" "${value}" "help: enum value ${value}"
        has "${bash_out}" "${value}" "bash: enum value ${value}"
        has "${zsh_out}" "${value}" "zsh: enum value ${value}"
        has "${fish_out}" "${value}" "fish: enum value ${value}"
        has "${nu_out}" "${value}" "nu: enum value ${value}"
    done

    testframework::section "errors / ошибки"
    local rc=0
    args::completion deploy.sh dash >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "1" "${rc}" "a shell without a generator: exit 1"

    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
