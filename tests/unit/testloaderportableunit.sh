#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testloaderportableunit.sh — bootstrap/loader.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testloaderportableunit.sh — bootstrap/loader.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# bootstrap/loader.sh is "@shell posix": load / bs_load must resolve @depends, refuse cycles,
# report failures and keep the registry and the stack consistent in every shell.
# bootstrap/loader.sh — "@shell posix": load / bs_load обязаны разбирать @depends, отказывать
# циклам, сообщать об ошибках и держать реестр и стек в порядке в любой оболочке.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly LOADER_SH="${BS_PROJECT_ROOT}/bootstrap/loader.sh"
readonly SHELL_SH="${BS_PROJECT_ROOT}/bootstrap/shell.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# mkroot — фиктивный корень BS_ROOT с модулями / a fake BS_ROOT with modules
mkroot() {
    local r="${T}/root"
    rm -rf "${r}"
    mkdir -p "${r}/m" "${r}/m dir"
    printf '%s\n' '# @depends m/b, m/c' 'echo "load a"; A_LOADED=1' > "${r}/m/a.sh"
    printf '%s\n' '# @depends   m/c   # trailing comment' 'echo "load b"' > "${r}/m/b.sh"
    printf '%s\n' 'echo "load c file=${BS_CURRENT_FILE##*/}"' > "${r}/m/c.sh"
    printf '%s\n' '# @depends m/cyc2' 'echo never' > "${r}/m/cyc1.sh"
    printf '%s\n' '# @depends m/cyc1' 'echo never' > "${r}/m/cyc2.sh"
    printf '%s\n' '# @depends m/missing' 'echo never' > "${r}/m/needs_missing.sh"
    printf '%s\n' 'return 3' > "${r}/m/fails.sh"
    printf '%s\n' '# @depends m/a' 'load m/c; echo "load nested"' > "${r}/m/nested.sh"
    printf '%s\n' 'echo "load spaced"' > "${r}/m dir/s p.sh"
    printf '%s\n' '# @depends m dir/s p' 'echo "load needs-spaced"' > "${r}/m/sp.sh"
    printf '%s\n' '# @shell bash4 — test' 'echo "load tiered"' > "${r}/m/tiered.sh"
    mkdir -p "${r}/lib"
    printf '%s\n' '# @shell bash4 — test' 'echo "load libmod"' > "${r}/lib/bashmod.sh"
}

# probe <shell> <snippet> — shell.sh и loader.sh подключены, BS_ROOT — фиктивный корень
probe() {
    local -r sh_bin="$1" snippet="$2"
    printf 'BS_CURRENT_FILE="%s"\n. "%s"\n. "%s"\n%s\n' "${SHELL_SH}" "${SHELL_SH}" "${LOADER_SH}" "${snippet}" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" BS_ROOT="${T}/root" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${LOADER_SH}'" "loader.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${LOADER_SH}'" "shellcheck -s sh is clean for bootstrap/loader.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${LOADER_SH}'" "bootstrap/loader.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${LOADER_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare|local| \\[\\[ |=~|read -ra|source '" "no shell-specific constructs in bootstrap/loader.sh" || true
}

test_behaviour() {
    local sh_bin sh_name out
    mkroot
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "$(probe "${sh_bin}" 'load m/a; echo "rc=$? A=${A_LOADED}"')" \
"load c file=c.sh
load b
load a
rc=0 A=1" "${sh_name}: dependencies load first, in order, with BS_CURRENT_FILE set"
        eq "$(probe "${sh_bin}" 'load m/a >/dev/null; load m/a; echo "rc=$?"; bs_load_is_loaded m/a; echo "a=$?"; bs_load_is_loaded m/zzz; echo "z=$?"; echo "depth=$(bs_load_stack_size) cur=[${BS_CURRENT_FILE##*/}]"')" \
"rc=0
a=0
z=1
depth=0 cur=[shell.sh]" "${sh_name}: a repeated load is a no-op; registry, stack and BS_CURRENT_FILE are restored"
        eq "$(probe "${sh_bin}" 'load m/cyc1; echo "rc=$? depth=$(bs_load_stack_size)"')" \
"BS: error: circular dependency detected: m/cyc1 m/cyc2 -> m/cyc1
BS: error: failed to load dependency 'm/cyc1' for module 'm/cyc2'
BS: error: failed to load dependency 'm/cyc2' for module 'm/cyc1'
rc=1 depth=0" "${sh_name}: a cycle is refused and the stack is clean"
        eq "$(probe "${sh_bin}" 'load m/needs_missing; echo "rc=$? depth=$(bs_load_stack_size)"; load m/nothere; echo "rc=$?"')" \
"BS: error: module file not found: ${T}/root/m/missing.sh
BS: error: failed to load dependency 'm/missing' for module 'm/needs_missing'
rc=1 depth=0
BS: error: module file not found: ${T}/root/m/nothere.sh
rc=1" "${sh_name}: a missing module and a missing dependency are reported"
        eq "$(probe "${sh_bin}" 'load m/fails; echo "rc=$? depth=$(bs_load_stack_size) cur=[${BS_CURRENT_FILE##*/}]"; bs_load_is_loaded m/fails; echo "loaded=$?"')" \
"BS: error: failed to load module 'm/fails'
rc=1 depth=0 cur=[shell.sh]
loaded=1" "${sh_name}: a module that returns non-zero is not marked loaded"
        eq "$(probe "${sh_bin}" 'load m/nested; echo "rc=$?"')" \
"load c file=c.sh
load b
load a
load nested
rc=0" "${sh_name}: a module may call load itself"
        eq "$(probe "${sh_bin}" 'load "m dir/s p"; echo "rc=$?"; load m/sp; echo "rc=$?"')" \
"load spaced
rc=0
load needs-spaced
rc=0" "${sh_name}: module paths with spaces"
        out="$(probe "${sh_bin}" 'BS_SHELL_STRICT=1 BS_ORIGIN_SHELL=dash; load m/tiered; echo "core-like rc=$?"; load lib/bashmod; echo "rc=$?"')"
        eq "$(printf '%s\n' "${out}" | grep -c "^load tiered$\|^core-like rc=0$\|cannot run from shell 'dash' (--strict-shell)\|^rc=1$")" "4" "${sh_name}: --strict-shell refuses a bash4 lib/ module from dash and lets a non-lib module through"
        eq "$(printf '%s\n' "${out}" | grep -c '^load libmod$')" "0" "${sh_name}: the refused module was not sourced"
        eq "$(probe "${sh_bin}" 'BS_ROOT=; load m/a; echo "rc=$?"; BS_ROOT=/no/such/dir; load m/a; echo "rc=$?"')" \
"BS: error: BS_ROOT is not set
rc=1
BS: error: BS_ROOT directory not found: /no/such/dir
rc=1" "${sh_name}: BS_ROOT is validated"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "$(probe "${sh_bin}" 'bs::load m/c; echo "rc=$?"')" "load c file=c.sh
rc=0" "${sh_name}: bs::load is an alias of bs_load"
    done
    eq "$(bs_load_is_loaded core/const; echo $?)" "0" "kernel: bs_load_is_loaded sees the core"
    eq "$(bs_load_stack_size)" "0" "kernel: the load stack is empty at rest"
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Behaviour in every shell / Поведение в каждой оболочке"; test_behaviour
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
