#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/teststrportableunit.sh — core/str.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/teststrportableunit.sh — core/str.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/str.sh is "@shell posix": the same answers in every shell for any content, literal replacing, whitespace trimming.
# core/str.sh — "@shell posix": одинаковые ответы в любой оболочке на любом содержимом, дословная замена, обрезка пробелов.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly MODULE_SH="${BS_PROJECT_ROOT}/core/str.sh"
# the files the probe sources, in dependency order / файлы, которые подключает проба, по порядку зависимостей
PROBE_FILES=(bootstrap/shell.sh core/prereq.sh core/str.sh)

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
        testframework::assert_command "'${sh_bin}' -n '${MODULE_SH}'" "str.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${MODULE_SH}'" "shellcheck -s sh is clean for core/str.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${MODULE_SH}'" "core/str.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${MODULE_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare| \\[\\[ |printf -v'" "no shell-specific constructs in core/str.sh" || true
}

test_case_and_trim() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "ABC DEF" "$(probe "${sh_bin}" 'bs_str_upper "abc def"')" "${sh_name}: upper"
        eq "abc def" "$(probe "${sh_bin}" 'bs_str_lower "ABC Def"')" "${sh_name}: lower"
        eq "привет ABC" "$(probe "${sh_bin}" 'bs_str_upper "привет abc"')" "${sh_name}: upper leaves non-ASCII alone (C locale)"
        eq "[a b]" "$(probe "${sh_bin}" 'printf "[%s]" "$(bs_str_trim "   a b  ")"')" "${sh_name}: trim spaces"
        eq "[a b]" "$(probe "${sh_bin}" 's=$(printf "\t \r a b \t\r\nX"); s=${s%X}; printf "[%s]" "$(bs_str_trim "$s")"')" "${sh_name}: trim tab, CR, LF"
        eq "[a  ]" "$(probe "${sh_bin}" 'printf "[%s]" "$(bs_str_ltrim "  a  ")"')" "${sh_name}: ltrim keeps the right side"
        eq "[  a]" "$(probe "${sh_bin}" 'printf "[%s]" "$(bs_str_rtrim "  a  ")"')" "${sh_name}: rtrim keeps the left side"
        eq "[]" "$(probe "${sh_bin}" 'printf "[%s]" "$(bs_str_trim "   ")"')" "${sh_name}: trim of only spaces is empty"
        eq "[]" "$(probe "${sh_bin}" 'printf "[%s]" "$(bs_str_trim "")"')" "${sh_name}: trim of empty"
        eq "[* a?]" "$(probe "${sh_bin}" 'printf "[%s]" "$(bs_str_trim "  * a? ")"')" "${sh_name}: trim keeps glob characters"
    done < <(testframework::posix_shells)
}

test_replace() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "a-b-c" "$(probe "${sh_bin}" 'bs_str_replace "a.b.c" . -')" "${sh_name}: a dot is literal"
        eq "axb" "$(probe "${sh_bin}" 'bs_str_replace "a*b" "*" x')" "${sh_name}: a star is literal"
        eq "abc" "$(probe "${sh_bin}" 'bs_str_replace "abc" "" x')" "${sh_name}: an empty pattern changes nothing"
        eq "aaaa" "$(probe "${sh_bin}" 'bs_str_replace "aa" a aa')" "${sh_name}: the replacement is not scanned again"
        eq "b b" "$(probe "${sh_bin}" 'bs_str_replace "a a" a b')" "${sh_name}: every occurrence"
        eq "ac" "$(probe "${sh_bin}" 'bs_str_replace "abc" b ""')" "${sh_name}: replace with nothing"
        eq "x/y" "$(probe "${sh_bin}" 'bs_str_replace "x\\y" "\\" "/"')" "${sh_name}: a backslash"
        eq "it is" "$(probe "${sh_bin}" 'bs_str_replace "it'"'"'s" "'"'"'s" " is"')" "${sh_name}: a quote"
        eq 'a$b' "$(probe "${sh_bin}" 'bs_str_replace "a@b" "@" "\$"')" "${sh_name}: a dollar in the replacement"
        eq "Прив1т" "$(probe "${sh_bin}" 'bs_str_replace "Привет" "е" "1"')" "${sh_name}: Cyrillic"
        eq "a b" "$(probe "${sh_bin}" 'bs_str_replace "a
b" "
" " "')" "${sh_name}: a newline as the pattern"
    done < <(testframework::posix_shells)
}

test_predicates() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=0 rc=1 rc=0" "$(probe "${sh_bin}" 'bs_str_contains abc b; printf "rc=%s " "$?"; bs_str_contains abc z; printf "rc=%s " "$?"; bs_str_contains abc ""; printf "rc=%s" "$?"')" "${sh_name}: contains (an empty needle is found)"
        eq "rc=1 rc=0" "$(probe "${sh_bin}" 'bs_str_contains abc "*"; printf "rc=%s " "$?"; bs_str_contains "a*c" "*"; printf "rc=%s" "$?"')" "${sh_name}: contains treats the needle literally"
        eq "rc=0 rc=1 rc=0" "$(probe "${sh_bin}" 'bs_str_starts_with abc ab; printf "rc=%s " "$?"; bs_str_starts_with abc bc; printf "rc=%s " "$?"; bs_str_starts_with abc ""; printf "rc=%s" "$?"')" "${sh_name}: starts_with"
        eq "rc=0 rc=1 rc=0" "$(probe "${sh_bin}" 'bs_str_ends_with abc bc; printf "rc=%s " "$?"; bs_str_ends_with abc ab; printf "rc=%s " "$?"; bs_str_ends_with abc ""; printf "rc=%s" "$?"')" "${sh_name}: ends_with"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_str_starts_with abc "?"; echo rc=$?')" "${sh_name}: starts_with treats ? literally"
    done < <(testframework::posix_shells)
}

test_repeat_join_split() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "ababab" "$(probe "${sh_bin}" 'bs_str_repeat ab 3')" "${sh_name}: repeat"
        eq "[]" "$(probe "${sh_bin}" 'printf "[%s]" "$(bs_str_repeat ab 0)"')" "${sh_name}: repeat 0 times"
        eq "--------" "$(probe "${sh_bin}" 'bs_str_repeat - 08')" "${sh_name}: repeat with a leading zero (08 is 8)"
        eq "rc=1 rc=1 rc=1" "$(probe "${sh_bin}" 'bs_str_repeat a x; printf "rc=%s " "$?"; bs_str_repeat a -1; printf "rc=%s " "$?"; bs_str_repeat a ""; printf "rc=%s" "$?"')" "${sh_name}: a bad count is 1"
        eq "a,b,c" "$(probe "${sh_bin}" 'IFS=$(printf "\n\t"); bs_str_join , a b c')" "${sh_name}: join under the strict IFS"
        eq "abc" "$(probe "${sh_bin}" 'bs_str_join "" a b c')" "${sh_name}: join with an empty separator"
        eq "[]" "$(probe "${sh_bin}" 'printf "[%s]" "$(bs_str_join ,)"')" "${sh_name}: join of nothing"
        eq "a b, c" "$(probe "${sh_bin}" 'bs_str_join ", " "a b" c')" "${sh_name}: join keeps words with spaces"
        eq "key" "$(probe "${sh_bin}" 'bs_str_before "key=val=2" "="')" "${sh_name}: before the first separator"
        eq "val=2" "$(probe "${sh_bin}" 'bs_str_after "key=val=2" "="')" "${sh_name}: after the first separator"
        eq "whole rc=1" "$(probe "${sh_bin}" 'printf "%s " "$(bs_str_before whole "=")"; bs_str_after whole "=" >/dev/null; echo rc=$?')" "${sh_name}: no separator: before is the whole string, after is 1"
        eq "rc=1 rc=1" "$(probe "${sh_bin}" 'bs_str_before a ""; printf "rc=%s " "$?"; bs_str_after a ""; printf "rc=%s" "$?"')" "${sh_name}: an empty separator is 1"
    done < <(testframework::posix_shells)
}

test_width_and_head() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "0 3 6 2 2" "$(probe "${sh_bin}" 'printf "%s %s %s %s %s" "$(bs_str_width "")" "$(bs_str_width abc)" "$(bs_str_width "привет")" "$(bs_str_width "─╭")" "$(bs_str_width "😀a")"')" "${sh_name}: width counts UTF-8 characters, not bytes"
        eq "[при] [ab😀] [] [abc] [привет]" "$(probe "${sh_bin}" 'printf "[%s] [%s] [%s] [%s] [%s]" "$(bs_str_head "привет мир" 3)" "$(bs_str_head "ab😀cd" 3)" "$(bs_str_head abc 0)" "$(bs_str_head abc 99)" "$(bs_str_head "привет" 6)"')" "${sh_name}: head takes N characters"
        eq "rc=1 rc=1" "$(probe "${sh_bin}" 'bs_str_head abc x >/dev/null; printf "rc=%s " "$?"; bs_str_head abc -1 >/dev/null; printf "rc=%s" "$?"')" "${sh_name}: a bad count is 1"
        eq "[a b]" "$(probe "${sh_bin}" 'printf "[%s]" "$(bs_str_head "a b c" 3)"')" "${sh_name}: head keeps a space inside"
    done < <(testframework::posix_shells)
}

test_no_aliases() {
    # the names str::upper ... belong to core/lang.sh: loading core/str.sh must not replace them
    local out
    out="$(env -i HOME="${T}/h" PATH="/usr/bin:/bin" BS_SILENT=1 bash -c ". '${BS_PROJECT_ROOT}/bootstrap/init.sh' >/dev/null 2>&1; str::replace 'a.b' '?' x; str::contains 'abc' 'b' && echo yes")"
    eq "xxx
yes" "${out}" "kernel: str::replace is still the glob version of core/lang.sh (? matches every character)"
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Case and trim / Регистр и обрезка"; test_case_and_trim
    testframework::section "Replace / Замена"; test_replace
    testframework::section "Predicates / Предикаты"; test_predicates
    testframework::section "Repeat, join, before/after / Повтор, склейка, до/после"; test_repeat_join_split
    testframework::section "Width and head / Ширина и начало"; test_width_and_head
    testframework::section "No aliases over lang.sh / Нет псевдонимов поверх lang.sh"; test_no_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
