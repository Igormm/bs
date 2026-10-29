#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testregexportableunit.sh — core/regex.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testregexportableunit.sh — core/regex.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/regex.sh is "@shell posix": the same ERE operations must give the same
# answers in every shell (grep -E / sed -E / awk).
# core/regex.sh — "@shell posix": одни и те же ERE-операции обязаны давать
# одинаковые ответы в любой оболочке (grep -E / sed -E / awk).

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly MODULE_SH="${BS_PROJECT_ROOT}/core/regex.sh"
# the files the probe sources, in dependency order / файлы, которые подключает проба, по порядку зависимостей
readonly PROBE_FILES=(bootstrap/shell.sh core/prereq.sh core/regex.sh)

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

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
        testframework::assert_command "'${sh_bin}' -n '${MODULE_SH}'" "regex.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${MODULE_SH}'" "shellcheck -s sh is clean for core/regex.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${MODULE_SH}'" "core/regex.sh is declared @shell posix" || true
}

test_match() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "0" "$(probe "${sh_bin}" 'bs_re_match "abc123" "^[a-z]+[0-9]+$"; echo $?')" "${sh_name}: match"
        eq "1" "$(probe "${sh_bin}" 'bs_re_match "abc" "[0-9]+"; echo $?')" "${sh_name}: no match"
        eq "0" "$(probe "${sh_bin}" 'bs_re_fullmatch "abc123" "[a-z]+[0-9]+"; echo $?')" "${sh_name}: fullmatch"
        eq "1" "$(probe "${sh_bin}" 'bs_re_fullmatch "abc123x" "[a-z]+[0-9]+"; echo $?')" "${sh_name}: fullmatch rejects a trailing character"
    done < <(testframework::posix_shells)
}

test_find_count() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "42" "$(probe "${sh_bin}" 'bs_re_find "foo 42 bar" "[0-9]+"')" "${sh_name}: find the first match"
        eq "3" "$(probe "${sh_bin}" 'bs_re_count "a1 b2 c3" "[0-9]"')" "${sh_name}: count matches"
        eq "0" "$(probe "${sh_bin}" 'bs_re_count "abc" "[0-9]"')" "${sh_name}: zero matches"
    done < <(testframework::posix_shells)
}

test_replace_split() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "aX bX" "$(probe "${sh_bin}" 'bs_re_replace "a1 b2" "[0-9]" "X"')" "${sh_name}: replace"
        eq "a b c" "$(probe "${sh_bin}" 'bs_re_split "a,b,c" "," | tr "\n" " " | sed "s/ $//"')" "${sh_name}: split"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_re_match "x" "[" 2>/dev/null; echo rc=$?')" "${sh_name}: an invalid pattern is status 2"
    done < <(testframework::posix_shells)
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Match / Совпадение"; test_match
    testframework::section "Find and count / Поиск и подсчёт"; test_find_count
    testframework::section "Replace and split / Замена и разбиение"; test_replace_split
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
