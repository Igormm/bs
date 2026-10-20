#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testutilsportableunit.sh — core/utils.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testutilsportableunit.sh — core/utils.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/utils.sh is "@shell posix": tempfile with its cleanup registry, split on the data layer,
# ensure_source and the root helpers must give the same answers in every shell.
# core/utils.sh — "@shell posix": tempfile с реестром очистки, split на слое данных, ensure_source
# и помощники корня обязаны давать одинаковые ответы в любой оболочке.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly UTILS_SH="${BS_PROJECT_ROOT}/core/utils.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — слой, prereq, const, data, logger, quiet и utils подключены, затем snippet
probe() {
    local -r sh_bin="$1" snippet="$2"
    local f
    : > "${T}/probe.sh"
    for f in bootstrap/shell.sh core/prereq.sh core/const.sh core/logger.sh core/quiet.sh core/data.sh core/utils.sh; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "${snippet}" >> "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" TMPDIR="${T}/tmp" BS_ROOT="${BS_PROJECT_ROOT}" BS_LOG_TIMESTAMP=false "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${UTILS_SH}'" "utils.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${UTILS_SH}'" "shellcheck -s sh is clean for core/utils.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${UTILS_SH}'" "core/utils.sh is declared @shell posix" || true
}

test_split() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "a|b|c" "$(probe "${sh_bin}" 'bs_utils_split A "a b c"; bs_arr_join A "|"')" "${sh_name}: split by the default space"
        eq "a|b|c" "$(probe "${sh_bin}" 'bs_utils_split A "  a   b c  "; bs_arr_join A "|"')" "${sh_name}: whitespace delimiters collapse and trim"
        eq "a||b" "$(probe "${sh_bin}" 'bs_utils_split A "a,,b" ","; bs_arr_join A "|"')" "${sh_name}: other delimiters keep empty fields"
        eq "a|b" "$(probe "${sh_bin}" 'bs_utils_split A "a,b," ","; bs_arr_join A "|"')" "${sh_name}: a trailing delimiter adds no empty field"
        eq "|a" "$(probe "${sh_bin}" 'bs_utils_split A ",a" ","; bs_arr_join A "|"')" "${sh_name}: a leading delimiter gives an empty first field"
        eq "a|b|c" "$(probe "${sh_bin}" 'bs_utils_split A "a , b:c" " ,:"; bs_arr_join A "|"')" "${sh_name}: several delimiter characters"
        eq "0" "$(probe "${sh_bin}" 'bs_utils_split A ""; bs_arr_len A')" "${sh_name}: an empty string gives an empty array"
        eq "*|b|c" "$(cd "${BS_PROJECT_ROOT}" && probe "${sh_bin}" 'bs_utils_split A "* b c"; bs_arr_join A "|"')" "${sh_name}: a field of * is not expanded as a glob"
    done < <(testframework::posix_shells)
}

test_tempfile() {
    local sh_bin sh_name out
    mkdir -p "${T}/tmp"
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "file" "$(probe "${sh_bin}" 'f=$(bs_utils_tempfile); [ -f "$f" ] && echo file')" "${sh_name}: tempfile creates a file"
        eq "dir" "$(probe "${sh_bin}" 'd=$(bs_utils_tempfile --dir); [ -d "$d" ] && echo dir')" "${sh_name}: tempfile --dir creates a directory"
        eq "gone gone" "$(probe "${sh_bin}" 'f=$(bs_utils_tempfile); d=$(bs_utils_tempfile --dir); bs_utils_tmp_cleanup; [ -e "$f" ] || printf "gone "; [ -e "$d" ] && printf kept || printf gone')" "${sh_name}: cleanup removes what tempfile created"
        eq "mine" "$(probe "${sh_bin}" 'f=$(bs_utils_tempfile mine); case "$f" in */mine.*) echo mine ;; esac')" "${sh_name}: the prefix is used"
        eq "rc=1" "$(probe "${sh_bin}" 'ln -s /etc/passwd "$UTILS_TMP_REGISTRY"; bs_utils_tempfile >/dev/null 2>&1; echo rc=$?; rm -f "$UTILS_TMP_REGISTRY"')" "${sh_name}: a symlinked registry is refused"
    done < <(testframework::posix_shells)
}

test_misc() {
    local sh_bin sh_name
    printf 'bs_t_hello() { printf hello; }\n' > "${T}/sourced.sh"
    printf '#only a comment\n' > "${T}/nofunc.sh"
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "hello" "$(probe "${sh_bin}" "bs_utils_ensure_source '${T}/sourced.sh' bs_t_hello && bs_t_hello")" "${sh_name}: ensure_source loads a file and checks the function"
        eq "rc=1" "$(probe "${sh_bin}" "bs_utils_ensure_source '${T}/nofunc.sh' bs_t_hello >/dev/null 2>&1; echo rc=\$?")" "${sh_name}: a missing function is 1"
        eq "rc=1" "$(probe "${sh_bin}" "bs_utils_ensure_source '${T}/missing.sh' bs_t_hello >/dev/null 2>&1; echo rc=\$?")" "${sh_name}: a missing file is 1"
        eq "${BS_PROJECT_ROOT}" "$(probe "${sh_bin}" 'bs_utils_detect_root >/dev/null; printf "%s" "$FRAMEWORK_ROOT"')" "${sh_name}: detect_root gives BS_ROOT"
        eq "/x/y" "$(probe "${sh_bin}" 'FRAMEWORK_ROOT=/tmp; bs_utils_boot_dir; BS_BOOTSTRAP_DIR=/x/y bs_utils_boot_dir; printf "%s" "$BOOT_DIR"')" "${sh_name}: boot_dir follows BS_BOOTSTRAP_DIR"
        eq "main" "$(probe "${sh_bin}" 'bs_shell_in_subshell && echo sub || echo main')" "${sh_name}: in_subshell is false in the main shell"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "a|b" "$(probe "${sh_bin}" 'utils::split A "a b"; bs_arr_join A "|"')" "${sh_name}: utils::split is an alias of bs_utils_split"
        eq "file" "$(probe "${sh_bin}" 'f=$(utils::tempfile); [ -f "$f" ] && echo file')" "${sh_name}: utils::tempfile is an alias"
    done
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "split"; test_split
    testframework::section "tempfile"; test_tempfile
    testframework::section "Other helpers / Прочее"; test_misc
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
