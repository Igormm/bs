#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testvarmetadataunit.sh — core/var.sh metadata layer under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testvarmetadataunit.sh — слой метаданных core/var.sh под dash, ash, ksh, mksh, zsh и bash
#
# bs_var_declare/schema/validate/list/describe plus the @ops and @on_invalid contracts are
# "@shell posix": every shell must give the same answers.
# bs_var_declare/schema/validate/list/describe и контракты @ops/@on_invalid — "@shell posix":
# каждая оболочка обязана давать одинаковые ответы.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly MODULE_SH="${BS_PROJECT_ROOT}/core/var.sh"
# the files the probe sources, in dependency order / файлы, которые подключает проба, по порядку зависимостей
readonly PROBE_FILES=(bootstrap/shell.sh core/prereq.sh core/var.sh)

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

test_declare_and_schema() {
    local sh_bin sh_name nl
    nl=$'\n'
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_var_declare A "type=int;ops=read,write" 2>/dev/null; echo rc=$?')" "${sh_name}: declare"
        eq "type=int;ops=read,write" "$(probe "${sh_bin}" 'bs_var_declare A "type=int;ops=read,write" 2>/dev/null; bs_var_schema A')" "${sh_name}: schema"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_var_declare A "type=int" 2>/dev/null; bs_var_declare A "type=int" 2>/dev/null; echo rc=$?')" "${sh_name}: redeclare with the same spec is idempotent"
        eq "rc=4" "$(probe "${sh_bin}" 'bs_var_declare A "type=int" 2>/dev/null; bs_var_declare A "type=uint" 2>/dev/null; echo rc=$?')" "${sh_name}: redeclare with a different spec is 4"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_var_declare "a b" "type=int" 2>/dev/null; echo rc=$?')" "${sh_name}: a bad name is 2"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_var_declare B "nokey" 2>/dev/null; echo rc=$?')" "${sh_name}: a segment without = is 2"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_var_declare C "type=int;bogus=1" 2>/dev/null; echo rc=$?')" "${sh_name}: an unknown key is 2"
        eq "A${nl}B" "$(probe "${sh_bin}" 'bs_var_declare A "type=int" 2>/dev/null; bs_var_declare B "type=uint" 2>/dev/null; bs_var_list')" "${sh_name}: list prints the declared names"
        eq "A=type=int" "$(probe "${sh_bin}" 'bs_var_declare A "type=int" 2>/dev/null; bs_var_describe A')" "${sh_name}: describe prints name=spec"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_var_schema NOPE_ZZ 2>/dev/null; echo rc=$?')" "${sh_name}: schema of an undeclared variable is 1"
    done < <(testframework::posix_shells)
}

test_validate() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "0 0 0 4 4 4 4" "$(probe "${sh_bin}" 'bs_var_declare I "type=int" 2>/dev/null; for v in 0 -5 42 1a 1.5 +1 x; do bs_var_validate I "$v" 2>/dev/null; printf "%s " "$?"; done | sed "s/ $//"')" "${sh_name}: int"
        eq "rc=4" "$(probe "${sh_bin}" 'bs_var_declare I "type=int" 2>/dev/null; bs_var_validate I "" 2>/dev/null; echo rc=$?')" "${sh_name}: int rejects an empty value"
        eq "0 0 4 4 4" "$(probe "${sh_bin}" 'bs_var_declare U "type=uint" 2>/dev/null; for v in 0 42 -1 1a x; do bs_var_validate U "$v" 2>/dev/null; printf "%s " "$?"; done | sed "s/ $//"')" "${sh_name}: uint"
        eq "0 0 0 0 4 4" "$(probe "${sh_bin}" 'bs_var_declare B "type=bool" 2>/dev/null; for v in 0 1 true false yes 2; do bs_var_validate B "$v" 2>/dev/null; printf "%s " "$?"; done | sed "s/ $//"')" "${sh_name}: bool"
        eq "0 0 0 4 4" "$(probe "${sh_bin}" 'bs_var_declare N "type=name" 2>/dev/null; for v in abc _a A1 "a b" 1a; do bs_var_validate N "$v" 2>/dev/null; printf "%s " "$?"; done | sed "s/ $//"')" "${sh_name}: name"
        eq "0 0 0 4" "$(probe "${sh_bin}" 'bs_var_declare E "type=enum:a|b|c" 2>/dev/null; for v in a b c d; do bs_var_validate E "$v" 2>/dev/null; printf "%s " "$?"; done | sed "s/ $//"')" "${sh_name}: enum"
        eq "0 0 4 4 4" "$(probe "${sh_bin}" 'bs_var_declare P "type=port" 2>/dev/null; for v in 1 65535 0 65536 abc; do bs_var_validate P "$v" 2>/dev/null; printf "%s " "$?"; done | sed "s/ $//"')" "${sh_name}: port"
        eq "0 4 4" "$(probe "${sh_bin}" 'bs_var_declare R "type=int;range=0..100" 2>/dev/null; for v in 50 101 -1; do bs_var_validate R "$v" 2>/dev/null; printf "%s " "$?"; done | sed "s/ $//"')" "${sh_name}: range"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_var_validate NO_SCHEMA_ZZ anything 2>/dev/null; echo rc=$?')" "${sh_name}: an undeclared variable has no constraints"
        eq "rc=4" "$(probe "${sh_bin}" 'bs_var_declare Z "type=zorg" 2>/dev/null; bs_var_validate Z 1 2>/dev/null; echo rc=$?')" "${sh_name}: an unknown type rejects everything"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_var_validate "a b" 1 2>/dev/null; echo rc=$?')" "${sh_name}: validate refuses a bad name"
    done < <(testframework::posix_shells)
}

test_ops() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "get=0 val=5 set=3 unset=3 append=3" "$(probe "${sh_bin}" 'bs_var_declare RO "type=int;ops=read" 2>/dev/null; RO=5; bs_var_get RO OUT; printf "get=%s val=%s " "$?" "$OUT"; bs_var_set RO 6 2>/dev/null; printf "set=%s " "$?"; bs_var_unset RO 2>/dev/null; printf "unset=%s " "$?"; bs_var_append RO x 2>/dev/null; printf "append=%s" "$?"')" "${sh_name}: ops=read blocks set/unset/append, allows get"
        eq "rc=0 rc=0" "$(probe "${sh_bin}" 'bs_var_declare RW "type=int;ops=read,write" 2>/dev/null; bs_var_set RW 7 2>/dev/null; printf "rc=%s " "$?"; bs_var_append RW 8 2>/dev/null; printf "rc=%s" "$?"')" "${sh_name}: ops=read,write allows set and append (via write)"
        eq "rc=3" "$(probe "${sh_bin}" 'bs_var_declare WO "type=int;ops=write" 2>/dev/null; WO=1; bs_var_get WO 2>/dev/null; echo rc=$?')" "${sh_name}: ops without read blocks get"
    done < <(testframework::posix_shells)
}

test_policy() {
    local sh_bin sh_name nl
    nl=$'\n'
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=4${nl}5" "$(probe "${sh_bin}" 'bs_var_declare E "type=int" 2>/dev/null; bs_var_set E 5 2>/dev/null; bs_var_set E nope 2>/dev/null; printf "rc=%s\n" "$?"; bs_var_get E')" "${sh_name}: an invalid value is refused and the old value stays"
        eq "rc=0${nl}bad" "$(probe "${sh_bin}" 'bs_var_declare G "type=int;on_invalid=ignore" 2>/dev/null; bs_var_set G bad 2>/dev/null; printf "rc=%s\n" "$?"; bs_var_get G')" "${sh_name}: on_invalid=ignore stores the raw value"
        eq "rc=0${nl}oops" "$(probe "${sh_bin}" 'bs_var_declare W "type=int;on_invalid=warn" 2>/dev/null; bs_var_set W oops 2>/dev/null; printf "rc=%s\n" "$?"; bs_var_get W')" "${sh_name}: on_invalid=warn stores and reports"
    done < <(testframework::posix_shells)
}

test_append_and_default() {
    local sh_bin sh_name nl
    nl=$'\n'
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=0${nl}123" "$(probe "${sh_bin}" 'bs_var_declare I "type=int" 2>/dev/null; bs_var_set I 12 2>/dev/null; bs_var_append I 3 2>/dev/null; printf "rc=%s\n" "$?"; bs_var_get I')" "${sh_name}: append keeps the value valid"
        eq "rc=4${nl}12" "$(probe "${sh_bin}" 'bs_var_declare I "type=int" 2>/dev/null; bs_var_set I 12 2>/dev/null; bs_var_append I x 2>/dev/null; printf "rc=%s\n" "$?"; bs_var_get I')" "${sh_name}: an append that breaks the type is refused"
        eq "rc=0${nl}60" "$(probe "${sh_bin}" 'bs_var_declare D "type=int;default=60" 2>/dev/null; bs_var_default D 2>/dev/null; printf "rc=%s\n" "$?"; bs_var_get D')" "${sh_name}: default uses the schema @default"
        eq "rc=0${nl}70" "$(probe "${sh_bin}" 'bs_var_declare D2 "type=int" 2>/dev/null; bs_var_default D2 70 2>/dev/null; printf "rc=%s\n" "$?"; bs_var_get D2')" "${sh_name}: default uses the given value when there is no schema default"
        eq "rc=4" "$(probe "${sh_bin}" 'bs_var_declare D3 "type=int;default=abc" 2>/dev/null; bs_var_default D3 2>/dev/null; echo rc=$?')" "${sh_name}: an invalid schema default is refused"
    done < <(testframework::posix_shells)
}

test_notify() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "var=N op=set result=ok" "$(probe "${sh_bin}" 'BS_VAR_AUDIT=1; bs_var_declare N "type=int" 2>/dev/null; bs_var_set N 5')" "${sh_name}: BS_VAR_AUDIT logs name, op and result (not the value)"
        eq "hook:H:set:ok" "$(probe "${sh_bin}" 'my_hook() { printf "hook:%s:%s:%s\n" "$1" "$2" "$3"; }; bs_var_declare H "type=int;on_change=hook:my_hook" 2>/dev/null; bs_var_set H 9 2>/dev/null')" "${sh_name}: on_change=hook:fn calls the hook"
    done < <(testframework::posix_shells)
}

test_eval_safety() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "clean" "$(probe "${sh_bin}" "bs_var_declare \"a;touch ${T}/pwned\" \"type=int\" 2>/dev/null; bs_var_declare \"\\\$(touch ${T}/pwned)\" \"type=int\" 2>/dev/null; [ -e \"${T}/pwned\" ] && echo created || echo clean")" "${sh_name}: declare never runs a name"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_var_declare __bs_var_v "type=int" 2>/dev/null; echo rc=$?')" "${sh_name}: the module's own temporaries are reserved"
    done < <(testframework::posix_shells)
}

main() {
    T="$(mktemp -d)"
    testframework::section "Declare, schema, list / declare, schema, list"; test_declare_and_schema
    testframework::section "Validation / Валидация"; test_validate
    testframework::section "Operations / Операции"; test_ops
    testframework::section "Policy / Политика"; test_policy
    testframework::section "Append and default / append и default"; test_append_and_default
    testframework::section "Notify / Уведомления"; test_notify
    testframework::section "Eval safety / Безопасность eval"; test_eval_safety
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
