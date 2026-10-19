#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testloaderportableunit.sh — bootstrap/loader.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testloaderportableunit.sh — bootstrap/loader.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# bootstrap/loader.sh is "@shell posix": bs_load must read @depends, order the loading, refuse cycles and
# keep its registry (the data layer) the same in every shell. The root is a temporary BS_ROOT whose
# core/ is the real one and whose lib/ holds small test modules.
# bootstrap/loader.sh — "@shell posix": bs_load читает @depends, соблюдает порядок, отказывает на циклах
# и ведёт реестр (слой данных) одинаково в любой оболочке. Корень — временный BS_ROOT: core/ настоящий,
# в lib/ лежат маленькие тестовые модули.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly LOADER_SH="${BS_PROJECT_ROOT}/bootstrap/loader.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# mod <path> <content> — a test module under the temporary root
mod() {
    mkdir -p "${T}/root/$(dirname "$1")"
    printf '%s\n' "$2" > "${T}/root/$1.sh"
}

# probe <shell> <snippet> — the loader is sourced with BS_ROOT/BS_BOOTSTRAP_DIR set, then the snippet (stdout+stderr);
# a fresh process under env -i
probe() {
    local -r sh_bin="$1" snippet="$2"
    printf 'BS_BOOTSTRAP_DIR="%s/bootstrap"\nBS_ROOT="%s/root"\nBS_CURRENT_FILE="%s"\n. "%s"\n%s\n' \
        "${BS_PROJECT_ROOT}" "${T}" "${LOADER_SH}" "${LOADER_SH}" "${snippet}" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
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
    testframework::assert_command "! grep -v '^#' '${LOADER_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare| \\[\\[ |printf -v'" "no shell-specific constructs in bootstrap/loader.sh" || true
}

make_modules() {
    mkdir -p "${T}/root" "${T}/h"
    ln -s "${BS_PROJECT_ROOT}/core" "${T}/root/core"
    mod lib/a 'ORDER="${ORDER:-}a "; A_LOADS=$((${A_LOADS:-0} + 1)); SEEN_A=$BS_CURRENT_FILE'
    mod lib/b '# @depends lib/a
ORDER="${ORDER:-}b "'
    mod lib/c '# @depends lib/a,   lib/b   # trailing comment
ORDER="${ORDER:-}c "'
    mod lib/nodeps 'TEXT="@depends lib/zz is only text here"; ORDER="${ORDER:-}n "'
    mod "lib/sp ace/mod" '# @depends lib/a
ORDER="${ORDER:-}s "'
    mod lib/cyc1 '# @depends lib/cyc2'
    mod lib/cyc2 '# @depends lib/cyc1'
    mod lib/broken 'return 1'
    mod lib/needs_missing '# @depends lib/does_not_exist'
    mod lib/nested 'bs_load lib/a; INNER_FILE=$BS_CURRENT_FILE'
    mod lib/strict '# @shell bash4 — test'
}

test_loading() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "a b" "$(probe "${sh_bin}" 'bs_load lib/b; printf "%s" "$ORDER" | sed "s/ $//"')" "${sh_name}: a dependency loads before its module"
        eq "a b c" "$(probe "${sh_bin}" 'bs_load lib/c; printf "%s" "$ORDER" | sed "s/ $//"')" "${sh_name}: a list with spaces and a trailing comment"
        eq "n" "$(probe "${sh_bin}" 'bs_load lib/nodeps; printf "%s" "$ORDER" | sed "s/ $//"')" "${sh_name}: @depends outside a comment is ignored"
        eq "a s" "$(probe "${sh_bin}" 'bs_load "lib/sp ace/mod"; printf "%s" "$ORDER" | sed "s/ $//"')" "${sh_name}: a space in the module path"
        eq "1" "$(probe "${sh_bin}" 'bs_load lib/a; bs_load lib/a; bs_load lib/b; printf "%s" "$A_LOADS"')" "${sh_name}: a module is sourced once"
        eq "rc=0 yes" "$(probe "${sh_bin}" 'bs_load lib/b; echo "rc=$?" | tr "\n" " "; bs_map_has bs_loaded_modules lib/a && echo yes')" "${sh_name}: loaded modules are in the registry"
        eq "no" "$(probe "${sh_bin}" 'bs_load lib/a; bs_map_has bs_loaded_modules lib/b && echo yes || echo no')" "${sh_name}: an unloaded one is not"
        eq "0" "$(probe "${sh_bin}" 'bs_load lib/c; bs_arr_len bs_load_stack')" "${sh_name}: the load stack is empty afterwards"
    done < <(testframework::posix_shells)
}

test_files() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "${T}/root/lib/a.sh" "$(probe "${sh_bin}" 'bs_load lib/a; printf "%s" "$SEEN_A"')" "${sh_name}: BS_CURRENT_FILE is the module while it is sourced"
        eq "${LOADER_SH}" "$(probe "${sh_bin}" 'bs_load lib/a; printf "%s" "$BS_CURRENT_FILE"')" "${sh_name}: BS_CURRENT_FILE is put back"
        eq "${T}/root/lib/nested.sh" "$(probe "${sh_bin}" 'bs_load lib/nested; printf "%s" "$INNER_FILE"')" "${sh_name}: a nested load restores the outer module's file"
    done < <(testframework::posix_shells)
}

test_errors() {
    local sh_bin sh_name out
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        out="$(probe "${sh_bin}" 'bs_load lib/nope; echo "rc=$?"; bs_arr_len bs_load_stack')"
        eq "BS: error: module file not found: ${T}/root/lib/nope.sh rc=1 0" "$(printf '%s' "${out}" | tr '\n' ' ' | sed 's/ $//')" "${sh_name}: a missing module is 1, the stack stays clean"
        out="$(probe "${sh_bin}" 'bs_load lib/cyc1; echo "rc=$?"; bs_arr_len bs_load_stack' | tr '\n' ' ')"
        case "${out}" in
            *"circular dependency detected: lib/cyc1 lib/cyc2 -> lib/cyc1"*"rc=1 0 ") eq "ok" "ok" "${sh_name}: a cycle is refused and named" ;;
            *) eq "a cycle message" "${out}" "${sh_name}: a cycle is refused and named" ;;
        esac
        out="$(probe "${sh_bin}" 'bs_load lib/broken; echo "rc=$?"; bs_map_has bs_loaded_modules lib/broken && echo loaded || echo not-loaded' | tr '\n' ' ')"
        eq "BS: error: failed to load module 'lib/broken' rc=1 not-loaded " "${out}" "${sh_name}: a module that fails is not marked loaded"
        out="$(probe "${sh_bin}" 'bs_load lib/needs_missing; echo "rc=$?"' | tr '\n' ' ')"
        case "${out}" in
            *"failed to load dependency 'lib/does_not_exist' for module 'lib/needs_missing'"*"rc=1 ") eq "ok" "ok" "${sh_name}: a failed dependency names both modules" ;;
            *) eq "a dependency message" "${out}" "${sh_name}: a failed dependency names both modules" ;;
        esac
        eq "BS: error: BS_ROOT is not set rc=1" "$(probe "${sh_bin}" 'unset BS_ROOT; bs_load lib/a; echo "rc=$?"' | tr '\n' ' ' | sed 's/ $//')" "${sh_name}: no BS_ROOT is 1"
        eq "retry-ok" "$(probe "${sh_bin}" 'bs_load lib/needs_missing >/dev/null 2>&1; bs_load lib/needs_missing 2>&1 | grep -qi circular && echo false-cycle || echo retry-ok')" "${sh_name}: a retry after a failure is not a false cycle"
    done < <(testframework::posix_shells)
}

test_strict_shell() {
    local sh_bin sh_name out
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        out="$(probe "${sh_bin}" 'BS_SHELL_STRICT=1 BS_ORIGIN_SHELL=dash; bs_load lib/strict >/dev/null 2>&1; echo "rc=$?"')"
        eq "rc=1" "${out}" "${sh_name}: --strict-shell refuses a bash4 lib module from dash"
        eq "rc=0" "$(probe "${sh_bin}" 'BS_SHELL_STRICT=0; bs_load lib/strict; echo "rc=$?"')" "${sh_name}: without --strict-shell it loads"
        eq "rc=0" "$(probe "${sh_bin}" 'BS_SHELL_STRICT=1 BS_ORIGIN_SHELL=dash; bs_load core/const; echo "rc=$?"')" "${sh_name}: core/ is always allowed"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "a b" "$(probe "${sh_bin}" 'load lib/b; printf "%s" "$ORDER" | sed "s/ $//"')" "${sh_name}: load is an alias of bs_load"
        eq "a" "$(probe "${sh_bin}" 'bs::load lib/a; printf "%s" "$ORDER" | sed "s/ $//"')" "${sh_name}: bs::load is an alias of bs_load"
    done
}

main() {
    T="$(mktemp -d)"
    make_modules
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Loading / Загрузка"; test_loading
    testframework::section "BS_CURRENT_FILE"; test_files
    testframework::section "Errors / Ошибки"; test_errors
    testframework::section "--strict-shell"; test_strict_shell
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
