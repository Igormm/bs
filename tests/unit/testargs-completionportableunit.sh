#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testargs-completionportableunit.sh — core/args-completion.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testargs-completionportableunit.sh — core/args-completion.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/args-completion.sh is "@shell posix": it must load after core/args, generate the same
# completion text in every shell, and refuse to load on its own. The checksums come from the
# previous bash implementation (a differential run).
# core/args-completion.sh — "@shell posix": он обязан подключаться после core/args, печатать
# одинаковый текст автодополнения в любой оболочке и отказываться от одиночного подключения.
# Контрольные суммы взяты у прежней реализации на bash (дифференциальный прогон).

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly COMPLETION_SH="${BS_PROJECT_ROOT}/core/args-completion.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

probe() {
    local -r sh_bin="$1" snippet="$2"
    local f
    : > "${T}/probe.sh"
    for f in bootstrap/shell.sh core/prereq.sh core/const.sh core/logger.sh core/quiet.sh core/data.sh core/utils.sh core/lang.sh core/errorhandler.sh core/args.sh; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "${snippet}" >> "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" BS_LOG_TIMESTAMP=false BS_LOG_COLOR=false "${sh_bin}" "${T}/probe.sh" 2>&1
}

probe_completion_only() {
    local -r sh_bin="$1"
    local f="${T}/completion-only.sh"
    : > "${f}"
    printf '. "%s"\necho "rc=$?"\n' "${COMPLETION_SH}" >> "${f}"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${f}" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

readonly DECL='bs_args_define cmd file...
bs_args_level 2 a b
bs_args_describe cmd "the command"
bs_args_flag verbose
bs_args_flag_describe verbose "Chatty"
bs_args_flag env value staging enum:dev,prod
bs_args_flag n value "" number'

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${COMPLETION_SH}'" "args-completion.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${COMPLETION_SH}'" "shellcheck -s sh is clean for core/args-completion.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${COMPLETION_SH}'" "core/args-completion.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${COMPLETION_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare -|mapfile|read -ra|=~'" "no shell-specific constructs in core/args-completion.sh" || true
}

test_load_order() {
    local sh_bin sh_name out
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        out="$(probe_completion_only "${sh_bin}")"
        eq "rc=1" "$(printf '%s\n' "${out}" | grep '^rc=' | tail -n 1)" "${sh_name}: refuses to load without core/args"
        testframework::assert_command "grep -q 'load core/args first' <<< '${out//\'/}'" "${sh_name}: names the missing dependency" || true
        eq "$(probe "${sh_bin}" 'command -v bs_args_completion_bash >/dev/null; echo "fn=$?"; . "'"${COMPLETION_SH}"'"; echo "rc=$?"')" "fn=0
rc=0" "${sh_name}: loads after core/args and is idempotent"
    done < <(testframework::posix_shells)
}

test_generators() {
    local sh_bin sh_name target want out
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        for target in "bash:4009108138 1754" "zsh:2601400582 424" "fish:3016321941 466" "nu:2844863020 523"; do
            want="${target#*:}"
            eq "$(probe "${sh_bin}" "${DECL}"$'\n'"bs_args_completion prog ${target%%:*}" | cksum | cut -d' ' -f1,2)" "${want}" "${sh_name}: ${target%%:*} completion matches the bash implementation"
        done
        eq "$(probe "${sh_bin}" 'bs_args_completion prog tcsh >/dev/null 2>&1; echo "unknown=$?"; bs_args_completion prog >/dev/null 2>&1; echo "empty=$?"' | tr '\n' ' ')" "unknown=1 empty=1 " "${sh_name}: refuses an unknown shell and an empty tree"
        out="$(probe "${sh_bin}" 'bs_args_flag env value staging enum:dev,prod; bs_args_flag n value "" number; bs_args_flag verbose; bs_args_completion_flags' | tr '\t' '|')"
        eq "env|enum|dev,prod
n|value|
verbose|bool|" "${out}" "${sh_name}: flags are sorted with kind and enum values"
    done < <(testframework::posix_shells)
}

test_alias() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "$(probe "${sh_bin}" 'args::flag verbose; args::completion prog zsh | head -n 1')" "#compdef prog" "${sh_name}: args::completion is an alias"
    done
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Load order / Порядок подключения"; test_load_order
    testframework::section "Generators / Генераторы"; test_generators
    testframework::section "Alias / Псевдоним"; test_alias
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
