#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testdataportableunit.sh — core/data.sh (arrays and maps) under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testdataportableunit.sh — core/data.sh (массивы и словари) под dash, ash, ksh, mksh, zsh и bash
#
# core/data.sh is "@shell posix": arrays and maps built on variables and eval must give the same
# answers in every shell, for any content (spaces, quotes, newlines, $, *, backslashes, Cyrillic).
# core/data.sh — "@shell posix": массивы и словари на переменных и eval обязаны давать одинаковые
# ответы в любой оболочке при любом содержимом.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly DATA_SH="${BS_PROJECT_ROOT}/core/data.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — слой, prereq и data подключены, затем snippet (stdout+stderr)
probe() {
    local -r sh_bin="$1" snippet="$2"
    local f
    : > "${T}/probe.sh"
    for f in bootstrap/shell.sh core/prereq.sh core/data.sh; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "${snippet}" >> "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${DATA_SH}'" "data.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${DATA_SH}'" "shellcheck -s sh is clean for core/data.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${DATA_SH}'" "core/data.sh is declared @shell posix" || true
}

# Набор «трудных» значений / The set of "hard" values
readonly HARD='bs_arr_new h "a b" "it'"'"'s" "" "*" "\$HOME" "back\\slash" "new
line" "Привет" "-n" "--"'

test_arrays() {
    local sh_bin sh_name out
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "3" "$(probe "${sh_bin}" 'bs_arr_new a x y z; bs_arr_len a')" "${sh_name}: arr new + len"
        eq "0" "$(probe "${sh_bin}" 'bs_arr_len nothing')" "${sh_name}: an unknown array has length 0"
        eq "x,y,z" "$(probe "${sh_bin}" 'bs_arr_new a x y z; bs_arr_join a ,')" "${sh_name}: join"
        eq "x y z" "$(probe "${sh_bin}" 'bs_arr_new a x y z; bs_arr_join a')" "${sh_name}: join with the default space"
        eq "y z" "$(probe "${sh_bin}" 'bs_arr_new a x y; bs_arr_push a z; bs_arr_get a 1; bs_arr_get a -1' | tr '\n' ' ' | sed 's/ $//')" "${sh_name}: push, get, negative get"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_arr_new a x; bs_arr_get a 5 >/dev/null; echo rc=$?')" "${sh_name}: get out of range is 1"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_arr_new a x; bs_arr_get a abc >/dev/null; echo rc=$?')" "${sh_name}: a non-numeric index is 1"
        eq "x,Q,z" "$(probe "${sh_bin}" 'bs_arr_new a x y z; bs_arr_set a 1 Q; bs_arr_join a ,')" "${sh_name}: set"
        eq "x,y,z,W" "$(probe "${sh_bin}" 'bs_arr_new a x y z; bs_arr_set a 3 W; bs_arr_join a ,')" "${sh_name}: set at the length appends"
        eq "z|x,y" "$(probe "${sh_bin}" 'bs_arr_new a x y z; bs_arr_pop a last; printf "%s|" "$last"; bs_arr_join a ,')" "${sh_name}: pop into a variable"
        eq "z" "$(probe "${sh_bin}" 'bs_arr_new a x y z; bs_arr_pop a')" "${sh_name}: pop prints when no variable is given"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_arr_new a; bs_arr_pop a v >/dev/null; echo rc=$?')" "${sh_name}: pop of an empty array is 1"
        eq "x|y,z" "$(probe "${sh_bin}" 'bs_arr_new a x y z; bs_arr_shift a first; printf "%s|" "$first"; bs_arr_join a ,')" "${sh_name}: shift into a variable"
        eq "x,z" "$(probe "${sh_bin}" 'bs_arr_new a x y z; bs_arr_remove_at a 1; bs_arr_join a ,')" "${sh_name}: remove_at"
        eq "1" "$(probe "${sh_bin}" 'bs_arr_new a x y z; bs_arr_index_of a y')" "${sh_name}: index_of"
        eq "yes no" "$(probe "${sh_bin}" 'bs_arr_new a x y; bs_arr_contains a y && printf "yes "; bs_arr_contains a q || printf "no"')" "${sh_name}: contains"
        eq "0" "$(probe "${sh_bin}" 'bs_arr_new a x y; bs_arr_clear a; bs_arr_len a')" "${sh_name}: clear"
        eq "a,b,c" "$(probe "${sh_bin}" 'bs_arr_from_lines a "a
b
c"; bs_arr_join a ,')" "${sh_name}: from_lines"
        eq "3 2" "$(probe "${sh_bin}" 'bs_arr_new a x y z; bs_arr_copy a b; bs_arr_pop a >/dev/null; printf "%s %s" "$(bs_arr_len b)" "$(bs_arr_len a)"')" "${sh_name}: copy is independent"
        # трудные значения переживают круг массив → аргументы / hard values survive array → arguments
        out="$(probe "${sh_bin}" "${HARD}"'; eval "$(bs_arr_to_args h)"; printf "%s|" "$#"; for x in "$@"; do printf "[%s]" "$x"; done')"
        eq "10|[a b][it's][][*][\$HOME][back\\slash][new
line][Привет][-n][--]" "${out}" "${sh_name}: hard values round-trip through to_args"
        eq "it's" "$(probe "${sh_bin}" 'bs_arr_new q "it'"'"'s"; bs_arr_get q 0')" "${sh_name}: a quote in a value"
        eq "[a][b]" "$(probe "${sh_bin}" 'show() { printf "[%s]" "$1"; }; bs_arr_new a a b; bs_arr_each a show')" "${sh_name}: each"
        eq "[x][y][x][y]" "$(probe "${sh_bin}" 'inner() { printf "[%s]" "$1"; }; outer() { bs_arr_each b inner; }; bs_arr_new a 1 2; bs_arr_new b x y; bs_arr_each a outer')" "${sh_name}: each inside each"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_arr_push "bad name" x 2>/dev/null; echo rc=$?')" "${sh_name}: a bad name is refused (2)"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_arr_push "a__b" x 2>/dev/null; echo rc=$?')" "${sh_name}: a name with __ is refused (2)"
    done < <(testframework::posix_shells)
}

test_maps() {
    local sh_bin sh_name out
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "v1" "$(probe "${sh_bin}" 'bs_map_set m k1 v1; bs_map_get m k1')" "${sh_name}: map set + get"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_map_get m nope >/dev/null; echo rc=$?')" "${sh_name}: a missing key is 1"
        eq "dflt" "$(probe "${sh_bin}" 'bs_map_get m nope dflt')" "${sh_name}: a default for a missing key"
        eq "yes no" "$(probe "${sh_bin}" 'bs_map_set m k v; bs_map_has m k && printf "yes "; bs_map_has m z || printf "no"')" "${sh_name}: has"
        eq "2" "$(probe "${sh_bin}" 'bs_map_set m a 1; bs_map_set m b 2; bs_map_set m a 3; bs_map_count m')" "${sh_name}: count (a key set twice counts once)"
        eq "3" "$(probe "${sh_bin}" 'bs_map_set m a 1; bs_map_set m a 3; bs_map_get m a')" "${sh_name}: overwrite"
        eq "b,a,c" "$(probe "${sh_bin}" 'bs_map_set m b 1; bs_map_set m a 2; bs_map_set m c 3; bs_map_keys m | tr "\n" , | sed "s/,$//"')" "${sh_name}: keys keep the insertion order"
        eq "a,c|2" "$(probe "${sh_bin}" 'bs_map_set m a 1; bs_map_set m b 2; bs_map_set m c 3; bs_map_remove m b; printf "%s|" "$(bs_map_keys m | tr "\n" , | sed "s/,$//")"; bs_map_count m')" "${sh_name}: remove"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_map_remove m nope; echo rc=$?')" "${sh_name}: removing a missing key is 1"
        eq "0" "$(probe "${sh_bin}" 'bs_map_set m a 1; bs_map_set m b 2; bs_map_clear m; bs_map_count m')" "${sh_name}: clear"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_map_set m a 1; bs_map_clear m; bs_map_has m a; echo rc=$?')" "${sh_name}: a cleared key is gone"
        # ключи с чем угодно / keys with anything in them
        out="$(probe "${sh_bin}" 'bs_map_set m "lib/io/streams" 1; bs_map_set m "a b" 2; bs_map_set m "it'"'"'s" 3; bs_map_set m "" 4; bs_map_set m "\$x*" 5; bs_map_set m "Привет" 6; bs_map_set m "a_b" 7; bs_map_set m "a-b" 8; bs_map_set m "a.b" 9; for k in "lib/io/streams" "a b" "it'"'"'s" "" "\$x*" "Привет" "a_b" "a-b" "a.b"; do printf "%s," "$(bs_map_get m "$k")"; done')"
        eq "1,2,3,4,5,6,7,8,9," "${out}" "${sh_name}: odd keys do not collide and come back right"
        eq "[x]=[1 2]" "$(probe "${sh_bin}" 'bs_map_set m x "1 2"; bs_map_each m show; ' | head -c 0; probe "${sh_bin}" 'show() { printf "[%s]=[%s]" "$1" "$2"; }; bs_map_set m x "1 2"; bs_map_each m show')" "${sh_name}: each gets key and value"
        eq "2" "$(probe "${sh_bin}" 'bs_map_set m a 1; bs_map_set m b 2; bs_map_keys_to m ks; bs_arr_len ks')" "${sh_name}: keys_to"
        eq "1|2" "$(probe "${sh_bin}" 'bs_map_set m1 a 1; bs_map_set m2 a 2; printf "%s|%s" "$(bs_map_get m1 a)" "$(bs_map_get m2 a)"')" "${sh_name}: two maps do not mix"
        eq "multi
line" "$(probe "${sh_bin}" 'bs_map_set m k "multi
line"; bs_map_get m k')" "${sh_name}: a value with a newline"
        eq "[v 1]rc=0" "$(probe "${sh_bin}" 'bs_map_set m k "v 1"; bs_map_get_to m k out; printf "[%s]rc=%s" "$out" "$?"')" "${sh_name}: get_to puts the value into a variable"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_map_get_to m nope out; echo rc=$?')" "${sh_name}: get_to of a missing key is 1"
        eq "multi
line" "$(probe "${sh_bin}" 'bs_map_set m k "multi
line"; bs_map_get_to m k out; printf "%s" "$out"')" "${sh_name}: get_to keeps a trailing-free newline value exactly"
    done < <(testframework::posix_shells)
}

test_quote() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "'a b'" "$(probe "${sh_bin}" 'bs_quote "a b"')" "${sh_name}: quote"
        eq "'it'\\''s'" "$(probe "${sh_bin}" 'bs_quote "it'"'"'s"')" "${sh_name}: quote of a single quote"
        eq "''" "$(probe "${sh_bin}" 'bs_quote ""')" "${sh_name}: quote of an empty string"
    done < <(testframework::posix_shells)
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Arrays / Массивы"; test_arrays
    testframework::section "Maps / Словари"; test_maps
    testframework::section "Quote / Кавычки"; test_quote
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
