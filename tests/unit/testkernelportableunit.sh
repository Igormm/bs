#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testkernelportableunit.sh — bootstrap/kernel.sh: the whole kernel in dash, ash, ksh, mksh, zsh and bash
# tests/unit/testkernelportableunit.sh — bootstrap/kernel.sh: всё ядро в dash, ash, ksh, mksh, zsh и bash
#
# One line — BS_ROOT=… . bootstrap/kernel.sh — must load the loader, all 15 core/ modules and the
# configuration in every shell, and the loaded kernel must work.
# Одна строка — BS_ROOT=… . bootstrap/kernel.sh — обязана подключить загрузчик, все 15 модулей
# core/ и конфигурацию в любой оболочке, и загруженное ядро должно работать.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly KERNEL_SH="${BS_PROJECT_ROOT}/bootstrap/kernel.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — ядро подключено одной строкой, затем snippet
probe() {
    local -r sh_bin="$1" snippet="$2"
    printf '. "%s"\n%s\n' "${KERNEL_SH}" "${snippet}" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" BS_ROOT="${BS_PROJECT_ROOT}" BS_LOG_TIMESTAMP=false BS_LOG_COLOR=false "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${KERNEL_SH}'" "kernel.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${KERNEL_SH}'" "shellcheck -s sh is clean for bootstrap/kernel.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${KERNEL_SH}'" "bootstrap/kernel.sh is declared @shell posix" || true
}

test_kernel_in_every_shell() {
    local sh_bin sh_name m mods
    mods="core/prereq core/lang core/const core/logger core/quiet core/fmt core/data core/errorhandler core/version core/utils core/config core/deps core/args"
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "$(probe "${sh_bin}" 'echo "rc=$?"' | tail -n 1)" "rc=0" "${sh_name}: kernel.sh loads without errors"
        eq "$(probe "${sh_bin}" 'n=0; for m in '"${mods}"'; do bs_load_is_loaded "$m" && n=$((n+1)); done; echo "loaded=$n depth=$(bs_load_stack_size)"' | tail -n 1)" "loaded=13 depth=0" "${sh_name}: all kernel modules are registered, the stack is empty"
        eq "$(probe "${sh_bin}" 'bs_log_info "kernel up"; bs_args_define a b; bs_args_parse a b; echo "args=$? $(bs_args_get 2)"; bs_arr_push q x y; echo "arr=$(bs_arr_join q ,)"; bs_map_set m k v; echo "map=$(bs_map_get m k)"; bs_is_number 42 && echo number; echo "ver=$(bs_version_get)"' | sed 's/ver=.*/ver=X/')" \
"[INFO ] kernel up
args=0 b
arr=x,y
map=v
number
ver=X" "${sh_name}: the loaded kernel works (log, args, data layer, predicates, version)"
        eq "$(probe "${sh_bin}" 'bs_config_get BS_LOG_LEVEL >/dev/null; echo "cfg=$?"; echo "home=${BS_HOME##*/}"' | tail -n 2 | tr '\n' ' ')" "cfg=0 home=$(basename "${BS_PROJECT_ROOT}") " "${sh_name}: configuration is loaded and BS_HOME defaults to BS_ROOT"
        eq "$(probe "${sh_bin}" '. "'"${KERNEL_SH}"'"; echo "again=$? depth=$(bs_load_stack_size)"' | tail -n 1)" "again=0 depth=0" "${sh_name}: sourcing kernel.sh twice is harmless"
        eq "$(env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" -c '. "'"${KERNEL_SH}"'"; echo "rc=$?"' 2>&1 | head -n 1 | cut -c1-40)" "BS: bootstrap/kernel.sh: задайте BS_ROOT" "${sh_name}: no BS_ROOT gives a clear message"
    done < <(testframework::posix_shells)
    # shellcheck disable=SC2034
    m=""
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "$(probe "${sh_bin}" 'log::info "hi"; utils::has ls && echo has; args::define a; echo "n=$(config::get BS_LOG_LEVEL >/dev/null; echo $?)"' | tr '\n' ' ')" "[INFO ] hi has n=0 " "${sh_name}: the old names with :: are aliases after kernel.sh"
    done
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "The whole kernel in every shell / Всё ядро в каждой оболочке"; test_kernel_in_every_shell
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
