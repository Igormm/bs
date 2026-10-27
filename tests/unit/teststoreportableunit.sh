#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/teststoreportableunit.sh — core/store.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/teststoreportableunit.sh — core/store.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/store.sh is "@shell posix": the values live in __bs_store_v_<name>, so there is no direct
# $name to bypass; every operation checks @ops (3) and @on_invalid (4).
# core/store.sh — "@shell posix": значения в __bs_store_v_<имя>, прямого $имя нет; каждая операция
# проверяет @ops (3) и @on_invalid (4).

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly MODULE_SH="${BS_PROJECT_ROOT}/core/store.sh"
readonly BUILD="${BS_PROJECT_ROOT}/scripts/build_store_helper.sh"
# the files the probe sources, in dependency order / файлы, которые подключает проба, по порядку зависимостей
readonly PROBE_FILES=(bootstrap/shell.sh core/prereq.sh core/var.sh core/store.sh)

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
        testframework::assert_command "'${sh_bin}' -n '${MODULE_SH}'" "store.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${MODULE_SH}'" "shellcheck -s sh is clean for core/store.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${MODULE_SH}'" "core/store.sh is declared @shell posix" || true
}

test_roundtrip() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=0 rc=0 5 rc=0 rc=0 rc=0 rc=1" "$(probe "${sh_bin}" 'bs_var_declare S "type=int;ops=read,write,unset,export" 2>/dev/null; r1=$?; bs_store_set S 5 2>/dev/null; r2=$?; bs_store_get S V; r3=$?; bs_store_has S; r4=$?; bs_store_unset S 2>/dev/null; r5=$?; bs_store_has S; r6=$?; printf "rc=%s rc=%s %s rc=%s rc=%s rc=%s rc=%s" "$r1" "$r2" "$V" "$r3" "$r4" "$r5" "$r6"')" "${sh_name}: set/get/has/unset roundtrip"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_var_declare S "type=int;ops=read,write" 2>/dev/null; bs_store_set S 5 2>/dev/null; [ "${S+x}" = x ] && echo set || echo rc=0')" "${sh_name}: the store value is not a shell variable"
        eq "S" "$(probe "${sh_bin}" 'bs_var_declare S "type=int;ops=read,write" 2>/dev/null; bs_store_set S 5 2>/dev/null; bs_store_list')" "${sh_name}: list"
        eq "rc=0 7" "$(probe "${sh_bin}" 'bs_var_declare E "type=int;ops=read,write,export" 2>/dev/null; bs_store_set E 7 2>/dev/null; bs_store_export E 2>/dev/null; printf "rc=%s %s" "$?" "$E"')" "${sh_name}: export creates a snapshot"
    done < <(testframework::posix_shells)
}

test_ops() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=3" "$(probe "${sh_bin}" 'bs_var_declare R "type=int;ops=read" 2>/dev/null; bs_store_set R 1 2>/dev/null; echo rc=$?')" "${sh_name}: ops=read blocks set"
        eq "set=0 get=3 unset=3 export=3" "$(probe "${sh_bin}" 'bs_var_declare W "type=int;ops=write" 2>/dev/null; bs_store_set W 1 2>/dev/null; printf "set=%s " "$?"; bs_store_get W 2>/dev/null; printf "get=%s " "$?"; bs_store_unset W 2>/dev/null; printf "unset=%s " "$?"; bs_store_export W 2>/dev/null; printf "export=%s" "$?"')" "${sh_name}: ops=write blocks get/unset/export"
    done < <(testframework::posix_shells)
}

test_validation() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=0 rc=4 5" "$(probe "${sh_bin}" 'bs_var_declare I "type=int;ops=read,write" 2>/dev/null; bs_store_set I 5 2>/dev/null; r1=$?; bs_store_set I nope 2>/dev/null; r2=$?; bs_store_get I V; printf "rc=%s rc=%s %s" "$r1" "$r2" "$V"')" "${sh_name}: an invalid value is refused and the old one stays"
        eq "rc=0 bad" "$(probe "${sh_bin}" 'bs_var_declare G "type=int;ops=read,write;on_invalid=ignore" 2>/dev/null; bs_store_set G bad 2>/dev/null; printf "rc=%s " "$?"; bs_store_get G')" "${sh_name}: on_invalid=ignore stores the raw value"
    done < <(testframework::posix_shells)
}

test_eval_safety() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "clean" "$(probe "${sh_bin}" "bs_store_set \"a;touch ${T}/pwned\" 1 2>/dev/null; bs_store_get \"\\\$(touch ${T}/pwned)\" 2>/dev/null; [ -e \"${T}/pwned\" ] && echo created || echo clean")" "${sh_name}: the store never runs a name"
    done < <(testframework::posix_shells)
}

test_backend() {
    local backend file sh_bin sh_name out snippet
    backend="$(sh "${BUILD}" 2>/dev/null || true)"
    if [[ -z "${backend}" || ! -x "${backend}" ]]; then
        testframework::skip "the C backend roundtrip" "no C compiler (cc/gcc/clang)"
        return 0
    fi
    file="${T}/store.db"
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        snippet=$(cat <<EOF
BS_STORE_BACKEND='${backend}' BS_STORE_FILE='${file}'
bs_var_declare C 'type=int;ops=read,write,unset,export' 2>/dev/null
bs_store_set C 42 2>/dev/null
EOF
)
        probe "${sh_bin}" "${snippet}" >/dev/null
        snippet=$(cat <<EOF
BS_STORE_BACKEND='${backend}' BS_STORE_FILE='${file}'
bs_var_declare C 'type=int;ops=read,write,unset,export' 2>/dev/null
bs_store_get C V; printf 'got=%s\n' "\$V"
EOF
)
        eq "got=42" "$(probe "${sh_bin}" "${snippet}")" "${sh_name}: the C backend persists across processes"
    done < <(testframework::posix_shells)
}

test_backend_fallback() {
    local out sh_bin
    sh_bin="$(command -v sh)"
    out="$(env -i PATH= CC=/nonexistent "${sh_bin}" "${BUILD}" 2>&1 || true)"
    eq "1" "$(printf '%s\n' "${out}" | grep -c 'no C compiler')" "the build script reports no compiler honestly"
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Roundtrip / Круговорот"; test_roundtrip
    testframework::section "Operations / Операции"; test_ops
    testframework::section "Validation / Валидация"; test_validation
    testframework::section "Eval safety / Безопасность eval"; test_eval_safety
    testframework::section "C backend / C-бэкенд"; test_backend
    testframework::section "Backend fallback / Фолбэк бэкенда"; test_backend_fallback
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
