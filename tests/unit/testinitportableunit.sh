#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testinitportableunit.sh — bootstrap/init.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testinitportableunit.sh — bootstrap/init.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# bootstrap/init.sh is "@shell posix": bash 4.2+ gets the whole kernel, every other shell its POSIX part (BS_KERNEL_MODE=posix).
# bootstrap/init.sh — "@shell posix": bash 4.2+ получает всё ядро, остальные оболочки — его POSIX-часть (BS_KERNEL_MODE=posix).

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly MODULE_SH="${BS_PROJECT_ROOT}/bootstrap/init.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — init.sh is sourced (BS_ENTRY_DIR set, as the entry points do), then the snippet
# (stdout+stderr); a fresh process under env -i
probe() {
    local -r sh_bin="$1" snippet="$2"
    printf 'BS_ENTRY_DIR="%s"\nBS_SILENT=1\n. "%s"\n%s\n' "${BS_PROJECT_ROOT}" "${MODULE_SH}" "${snippet}" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${MODULE_SH}'" "init.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${MODULE_SH}'" "shellcheck -s sh is clean for bootstrap/init.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${MODULE_SH}'" "bootstrap/init.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${MODULE_SH}' | grep -v 'shell-gate' | grep -E 'BASH_|ZSH_|FUNCNAME|declare| \\[\\[ |printf -v'" "no shell-specific constructs in bootstrap/init.sh outside the shell-gate lines" || true
}

test_modes() {
    local sh_bin sh_name want_mode want_count want_bridge
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        want_mode=posix; want_count=17; want_bridge=no-bridge
        if [[ "${sh_name}" == bash ]]; then want_mode=full; want_count=20; want_bridge=bridge; fi
        eq "mode=${want_mode} modules=${want_count}" "$(probe "${sh_bin}" 'printf "mode=%s modules=%s" "$BS_KERNEL_MODE" "$(printf %s "$__bs_ld_loaded" | grep -c .)"')" "${sh_name}: the kernel mode and the number of loaded modules"
        eq "ok" "$(probe "${sh_bin}" 'bs_load_is_loaded core/logger && bs_load_is_loaded core/deps && bs_load_is_loaded core/num && echo ok')" "${sh_name}: logger, deps and num are loaded"
        eq "ok|false" "$(probe "${sh_bin}" 'bs_load_is_loaded core/config && printf "ok|"; bs_config_get BS_FILES_ATOMIC')" "${sh_name}: config is loaded and bs_config_load ran, in both kernel modes"
        eq "ok|dir" "$(probe "${sh_bin}" 'if bs_load_is_loaded core/lang && bs_is_dir /; then printf "ok|dir"; fi')" "${sh_name}: lang is loaded and bs_is_dir works, in both kernel modes"
        eq "${want_bridge}" "$(probe "${sh_bin}" 'if bs_load_is_loaded lib/compat/lang && bs_load_is_loaded lib/compat/deps && bs_load_is_loaded lib/compat/args; then echo bridge; else echo no-bridge; fi')" "${sh_name}: the bridges lib/compat/lang, lib/compat/deps and lib/compat/args are loaded only in the full mode"
        eq "loaded|ondemand|ok" "$(probe "${sh_bin}" 'if bs_load_is_loaded core/args; then printf "loaded|"; else printf "ondemand|"; fi; if bs_load_is_loaded core/calc; then printf "loaded|"; else printf "ondemand|"; fi; bs_args_define go; bs_args_parse go >/dev/null 2>&1 && echo ok')" "${sh_name}: kernel.sh loads args at start, calc is on demand, in both kernel modes"
    done < <(testframework::posix_shells)
}

test_usable() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "HELLO 3221225472 has" "$(probe "${sh_bin}" 'printf "%s %s " "$(bs_str_upper hello)" "$(bs_num_mul 3 1073741824)"; bs_utils_has ls && echo has')" "${sh_name}: str, num and utils work after init"
        eq "ok" "$(probe "${sh_bin}" 'bs_arr_new a x y; bs_map_set m k v; [ "$(bs_arr_len a)" = 2 ] && [ "$(bs_map_get m k)" = v ] && echo ok')" "${sh_name}: the data layer works after init"
        eq "[INFO ] hello" "$(probe "${sh_bin}" 'BS_LOG_TIMESTAMP=false BS_LOG_COLOR=never bs_log_info hello')" "${sh_name}: the logger works after init"
        eq "rc=0 rc=0" "$(probe "${sh_bin}" '. "'"${MODULE_SH}"'"; printf "rc=%s " "$?"; bs_load core/const; printf "rc=%s" "$?"')" "${sh_name}: init twice is a no-op and bs_load works"
        eq "ok" "$(probe "${sh_bin}" '[ "$BS_ROOT" = "'"${BS_PROJECT_ROOT}"'" ] && [ "$BS_INITIALIZED" = 1 ] && [ "$BS_HOME" = "$BS_ROOT" ] && echo ok')" "${sh_name}: BS_ROOT, BS_HOME and BS_INITIALIZED"
    done < <(testframework::posix_shells)
}

test_directory() {
    local sh_name sh_bin out
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        out="$(env -i HOME="${T}/h" PATH="/usr/bin:/bin" BS_SILENT=1 "${sh_bin}" -c ". '${MODULE_SH}'; [ \"\$BS_ROOT\" = '${BS_PROJECT_ROOT}' ] && echo found")"
        eq "found" "${out}" "${sh_name}: the directory is found from the path of init.sh, with no BS_ENTRY_DIR"
    done
    out="$(env -i HOME="${T}/h" PATH="/usr/bin:/bin" BS_SILENT=1 "$(command -v dash)" -c ". '${MODULE_SH}'; echo rc=\$?" 2>&1 | tr '\n' ' ')"
    case "${out}" in
        *"set BS_BOOTSTRAP_DIR, BS_ENTRY_DIR or BS_ROOT"*) eq ok ok "dash: without any directory hint init.sh says what to set" ;;
        *) eq "a hint" "${out}" "dash: without any directory hint init.sh says what to set" ;;
    esac
    out="$(env -i HOME="${T}/h" PATH="/usr/bin:/bin" bash "${MODULE_SH}" 2>&1 | head -n 1 || true)"
    eq "ERROR: This script must be sourced, not executed." "${out}" "bash: executing init.sh is refused"
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "ok" "$(probe "${sh_bin}" 'load core/const && usage >/dev/null && echo ok')" "${sh_name}: load and usage are aliases"
    done
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Kernel modes / Режимы ядра"; test_modes
    testframework::section "The kernel after init / Ядро после init"; test_usable
    testframework::section "Directory and direct run / Каталог и прямой запуск"; test_directory
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
