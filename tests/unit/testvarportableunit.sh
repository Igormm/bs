#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testvarportableunit.sh — core/var.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testvarportableunit.sh — core/var.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/var.sh is "@shell posix": names are checked before every eval, values go by reference, any content survives.
# core/var.sh — "@shell posix": имена проверяются до каждого eval, значения идут по ссылке, любое содержимое сохраняется.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly MODULE_SH="${BS_PROJECT_ROOT}/core/var.sh"
# the files the probe sources, in dependency order / файлы, которые подключает проба, по порядку зависимостей
PROBE_FILES=(bootstrap/shell.sh core/prereq.sh core/var.sh)

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
        testframework::assert_command "'${sh_bin}' -n '${MODULE_SH}'" "var.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${MODULE_SH}'" "shellcheck -s sh is clean for core/var.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${MODULE_SH}'" "core/var.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${MODULE_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare| \\[\\[ |printf -v'" "no shell-specific constructs in core/var.sh" || true
}

test_names() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "ok ok ok" "$(probe "${sh_bin}" 'for n in a _a A1; do bs_var_is_name "$n" && printf "ok "; done | sed "s/ $//"')" "${sh_name}: valid names"
        eq "no no no no no no" "$(probe "${sh_bin}" 'for n in "" 1a "a b" a-b "a;b" "a\$b"; do bs_var_is_name "$n" || printf "no "; done | sed "s/ $//"')" "${sh_name}: invalid names"
        eq "rc=2 rc=2 rc=2 rc=2 rc=2 rc=2" "$(probe "${sh_bin}" 'for f in bs_var_set bs_var_get bs_var_unset bs_var_default bs_var_append bs_var_is_set; do "$f" "a b" x 2>/dev/null; printf "rc=%s " "$?"; done | sed "s/ $//"')" "${sh_name}: every function refuses a bad name with 2"
        eq "clean" "$(probe "${sh_bin}" "bs_var_set \"a;touch ${T}/pwned\" 1 2>/dev/null; bs_var_get \"\\\$(touch ${T}/pwned)\" 2>/dev/null; [ -e \"${T}/pwned\" ] && echo created || echo clean")" "${sh_name}: a name with a command is never executed"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_var_set __bs_var_v x 2>/dev/null; echo rc=$?')" "${sh_name}: the module's own temporaries are reserved"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_var_set X 1; bs_var_get X __bs_var_v 2>/dev/null; echo rc=$?')" "${sh_name}: the output variable is checked too"
    done < <(testframework::posix_shells)
}

test_values() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "a b" "$(probe "${sh_bin}" 'bs_var_set X "a b"; bs_var_get X')" "${sh_name}: set + get"
        eq "it's" "$(probe "${sh_bin}" 'bs_var_set X "it'"'"'s"; bs_var_get X')" "${sh_name}: a quote"
        eq "*" "$(probe "${sh_bin}" 'bs_var_set X "*"; bs_var_get X')" "${sh_name}: a star is not globbed"
        eq '$HOME' "$(probe "${sh_bin}" 'bs_var_set X "\$HOME"; bs_var_get X')" "${sh_name}: a dollar is not expanded"
        eq 'back\slash' "$(probe "${sh_bin}" 'bs_var_set X "back\\slash"; bs_var_get X')" "${sh_name}: a backslash"
        eq "Привет" "$(probe "${sh_bin}" 'bs_var_set X "Привет"; bs_var_get X')" "${sh_name}: Cyrillic"
        eq "-n" "$(probe "${sh_bin}" 'bs_var_set X "-n"; bs_var_get X')" "${sh_name}: a value that looks like an option"
        eq "multi
line" "$(probe "${sh_bin}" 'bs_var_set X "multi
line"; bs_var_get X')" "${sh_name}: a newline"
        eq "[]" "$(probe "${sh_bin}" 'bs_var_set X ""; printf "[%s]" "$X"')" "${sh_name}: an empty value"
        eq "5" "$(probe "${sh_bin}" 'bs_var_set X 5; bs_var_get X Y; printf "%s" "$Y"')" "${sh_name}: get into a variable (no subshell)"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_var_get NOPE_ZZ; echo rc=$?')" "${sh_name}: an unset variable is 1"
        eq "rc=0" "$(probe "${sh_bin}" 'E=; bs_var_is_set E; echo rc=$?')" "${sh_name}: set but empty is set"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_var_is_set NOPE_ZZ; echo rc=$?')" "${sh_name}: is_set of an unset one is 1"
        eq "rc=1" "$(probe "${sh_bin}" 'X=1; bs_var_unset X; bs_var_is_set X; echo rc=$?')" "${sh_name}: unset"
        eq "d x d" "$(probe "${sh_bin}" 'bs_var_default A d; B=x; bs_var_default B d; C=; bs_var_default C d; printf "%s %s %s" "$A" "$B" "$C"')" "${sh_name}: default fills unset and empty, keeps a value"
        eq "ab c" "$(probe "${sh_bin}" 'bs_var_append A a; bs_var_append A b; bs_var_append A " c"; printf "%s" "$A"')" "${sh_name}: append (also to an unset one)"
    done < <(testframework::posix_shells)
}

test_readonly() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=0 rc=1 rc=2" "$(probe "${sh_bin}" 'readonly RO_ZZ=1; W=1; bs_var_is_readonly RO_ZZ; printf "rc=%s " "$?"; bs_var_is_readonly W; printf "rc=%s " "$?"; bs_var_is_readonly "a b" 2>/dev/null; printf "rc=%s" "$?"')" "${sh_name}: is_readonly, and the probe does not end the caller"
    done < <(testframework::posix_shells)
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Names and eval safety / Имена и безопасность eval"; test_names
    testframework::section "Values / Значения"; test_values
    testframework::section "Read-only / Только для чтения"; test_readonly
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
