#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testbaseportableunit.sh — bootstrap/base.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testbaseportableunit.sh — bootstrap/base.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# bootstrap/base.sh is "@shell posix": strict mode, the local bin in PATH and the version gate must act the same in every shell.
# bootstrap/base.sh — "@shell posix": строгий режим, ~/.local/bin в PATH и гейт версии обязаны вести себя одинаково в любой оболочке.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly MODULE_SH="${BS_PROJECT_ROOT}/bootstrap/base.sh"
# the files the probe sources, in dependency order / файлы, которые подключает проба, по порядку зависимостей
PROBE_FILES=(bootstrap/shell.sh bootstrap/base.sh)

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — the files are sourced (BS_CURRENT_FILE is set, as the loader does), then the snippet
# (stdout+stderr); a fresh process under env -i: the guard makes a second source in one process a no-op
probe() {
    local -r sh_bin="$1" snippet="$2"
    local f
    : > "${T}/probe.sh"
    for f in "${PROBE_FILES[@]}"; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "${snippet}" >> "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${MODULE_SH}'" "base.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${MODULE_SH}'" "shellcheck -s sh is clean for bootstrap/base.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${MODULE_SH}'" "bootstrap/base.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${MODULE_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare| \\[\\[ |printf -v'" "no shell-specific constructs in bootstrap/base.sh" || true
}

test_strict_and_path() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "flags-ok ifs-ok" "$(probe "${sh_bin}" 'bs_strict; case $- in *e*) case $- in *u*) printf "flags-ok ";; esac;; esac; [ "$IFS" = "$(printf "\n\t")" ] && printf "ifs-ok"')" "${sh_name}: bs_strict sets -e, -u and the strict IFS"
        eq "ok" "$(probe "${sh_bin}" 'bs_strict; if (set -o pipefail) 2>/dev/null; then if false | true; then echo broken; else echo ok; fi; else echo ok; fi')" "${sh_name}: pipefail is on where the shell has it"
        eq "/h/.local/bin:/usr/bin" "$(probe "${sh_bin}" 'HOME=/h PATH=/usr/bin; bs_append_local_bin_to_path; printf "%s" "$PATH"')" "${sh_name}: ~/.local/bin is prepended"
        eq "/h/.local/bin:/usr/bin" "$(probe "${sh_bin}" 'HOME=/h PATH=/usr/bin; bs_append_local_bin_to_path; bs_append_local_bin_to_path; printf "%s" "$PATH"')" "${sh_name}: ... only once"
        eq "/usr/bin:/h/.local/bin:/bin" "$(probe "${sh_bin}" 'HOME=/h PATH=/usr/bin:/h/.local/bin:/bin; bs_append_local_bin_to_path; printf "%s" "$PATH"')" "${sh_name}: ... and not again when it is in the middle"
    done < <(testframework::posix_shells)
}

test_version_gate() {
    local sh_bin sh_name want ver_rc
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        want=0; [[ "${sh_name}" == bash ]] && want=1
        ver_rc=1; [[ "${sh_name}" == bash || "${sh_name}" == zsh ]] && ver_rc=0
        eq "ok" "$(probe "${sh_bin}" '[ "$(bs_shell_name)" = "$(bs_shell_family)" ] && echo ok')" "${sh_name}: bs_shell_name is the family"
        eq "${want}" "$(probe "${sh_bin}" 'bs_shell_ok')" "${sh_name}: bs_shell_ok is 1 only for bash 4.2+"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_shell_ensure_version 0 0; echo rc=$?')" "${sh_name}: version 0.0 is always met"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_shell_ensure_version 99 0 2>/dev/null; echo rc=$?')" "${sh_name}: version 99.0 is never met"
        eq "ERROR: bash 99.0+ required, found" "$(probe "${sh_bin}" 'bs_shell_ensure_version 99 0 2>&1 | sed "s/^ERROR: [a-z]* /ERROR: bash /" | cut -c1-33')" "${sh_name}: the message names the requirement"
        eq "ERROR: ensure_version: required version must be numbers, got x.2 rc=1" "$(probe "${sh_bin}" 'bs_shell_ensure_version x 2 2>&1; echo rc=$?' | tr '\n' ' ' | sed 's/ $//')" "${sh_name}: a non-number is refused"
        eq "rc=${ver_rc}" "$(probe "${sh_bin}" 'bs_shell_ensure_version 4 "" 2>/dev/null; echo rc=$?')" "${sh_name}: an empty minor falls back to the default 2 (the gate compares the version number: bash and zsh are 5.x)"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "ok" "$(probe "${sh_bin}" 'bs::strict; bs::append_local_bin_to_path; bs::shell::ensure_version 0 0 && [ "$(bs::shell::name)" = "$(bs_shell_name)" ] && echo ok')" "${sh_name}: the old bs:: names are aliases"
    done
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Strict mode and PATH / Строгий режим и PATH"; test_strict_and_path
    testframework::section "Version gate / Гейт версии"; test_version_gate
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
