#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testcacheunit.sh — core/cache.sh through the loader and the bs cache CLI: cross-process, C backend, strict mode
# tests/unit/testcacheunit.sh — core/cache.sh через загрузчик и CLI bs cache: cross-process, C-бэкенд, строгий режим

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
export BS_HOME="${BS_PROJECT_ROOT}"
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

load "core/cache"

T=""

test_loaded_via_load() {
    testframework::assert_command 'declare -f bs_cache_put >/dev/null' "load core/cache defines bs_cache_put"
    testframework::assert_command 'declare -f cache::get >/dev/null' "the cache::get alias exists in bash"
    testframework::assert_command 'bs_load_is_loaded core/cache' "the loader marks core/cache as loaded"
}

test_cli_cross_process() {
    local out rc=0
    export BS_CACHE_DIR="${T}/cli"
    "${BS_PROJECT_ROOT}/bs" cache put shared "cross process" --fp fp1 >/dev/null
    out="$("${BS_PROJECT_ROOT}/bs" cache get shared --fp fp1)"
    testframework::assert_equal "cross process" "${out}" "a value put by one bs process is read by another (L2)"
    rm -f "${BS_CACHE_DIR}"/v/*
    out="$("${BS_PROJECT_ROOT}/bs" cache get shared --fp fp1)"
    testframework::assert_equal "cross process" "${out}" "with L2 removed the cold L3 answers and promotes"
    "${BS_PROJECT_ROOT}/bs" cache get shared --fp other >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "1" "${rc}" "a wrong fingerprint is a miss via the CLI"
    out="$("${BS_PROJECT_ROOT}/bs" cache list)"
    testframework::assert_command "grep -q 'key=shared fp=fp1' <<< '${out}'" "the CLI list shows the readable manifest"
    "${BS_PROJECT_ROOT}/bs" cache delete shared >/dev/null
    out="$("${BS_PROJECT_ROOT}/bs" cache list)"
    testframework::assert_command "grep -q 'CACHE EMPTY' <<< '${out}'" "an empty cache prints the framed noop notice"
    unset BS_CACHE_DIR
}

test_cli_flags_and_errors() {
    local rc=0
    export BS_CACHE_DIR="${T}/flags"
    "${BS_PROJECT_ROOT}/bs" cache put k v --fp=f1 --ttl=60 >/dev/null
    testframework::assert_command "'${BS_PROJECT_ROOT}/bs' cache get k --fp=f1 | grep -q '^v$'" "--fp= and --ttl= forms work"
    rc=0; "${BS_PROJECT_ROOT}/bs" cache put 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "put without KEY/VALUE is 2"
    rc=0; "${BS_PROJECT_ROOT}/bs" cache get 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "get without KEY is 2"
    rc=0; "${BS_PROJECT_ROOT}/bs" cache bogus 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "an unknown subcommand is 2"
    rc=0; "${BS_PROJECT_ROOT}/bs" cache get k --fp 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "--fp without a value is 2"
    unset BS_CACHE_DIR
}

test_c_backend() {
    local backend out
    backend="$(sh "${BS_PROJECT_ROOT}/scripts/build_store_helper.sh" 2>/dev/null || true)"
    if [[ -z "${backend}" ]]; then
        printf '  ⊘ C backend skipped: no compiler / нет компилятора\n'
        return 0
    fi
    export BS_CACHE_DIR="${T}/cstore" BS_CACHE_L3=cstore BS_STORE_BACKEND="${backend}"
    bs_cache_init
    testframework::assert_equal "cstore" "${__bs_cache_l3}" "the C backend is picked when wired"
    bs_cache_put ck fp1 "via C store"
    rm -f "${BS_CACHE_DIR}"/v/*
    bs_map_clear cacheV
    bs_map_clear cacheF
    bs_cache_init
    out="$(bs_cache_get ck fp1)"
    testframework::assert_equal "via C store" "${out}" "the C backend survives L2 removal (base64 values)"
    testframework::assert_command "grep -q 'cache_' '${BS_CACHE_DIR}/l3.store'" "the C store file is readable text"
    unset BS_CACHE_DIR BS_CACHE_L3 BS_STORE_BACKEND
}

test_strict_mode_safety() {
    local out rc=0
    out="$(bash -c '
        set -euo pipefail
        BS_ROOT="'"${BS_PROJECT_ROOT}"'"
        export BS_CACHE_DIR="'"${T}"'/strict"
        BS_CURRENT_FILE="${BS_ROOT}/bootstrap/shell.sh"; . "${BS_ROOT}/bootstrap/shell.sh"
        BS_CURRENT_FILE="${BS_ROOT}/core/prereq.sh"; . "${BS_ROOT}/core/prereq.sh"
        BS_CURRENT_FILE="${BS_ROOT}/core/data.sh"; . "${BS_ROOT}/core/data.sh"
        BS_CURRENT_FILE="${BS_ROOT}/core/cache.sh"; . "${BS_ROOT}/core/cache.sh"
        bs_cache_init
        bs_cache_put k fp1 v
        if bs_cache_get k other 2>/dev/null; then echo bad; else echo "rc=$?"; fi
        bs_cache_main stats >/dev/null
        bs_cache_main list >/dev/null
        echo alive
    ' 2>&1)" || rc=$?
    testframework::assert_equal "0" "${rc}" "a miss does not kill a set -e script"
    testframework::assert_equal "rc=1
alive" "${out}" "the miss is a status, the script lives on"
}

test_example_runs() {
    local out
    out="$("${BS_PROJECT_ROOT}/bs" "${BS_PROJECT_ROOT}/example_core/cache_demo.sh" 2>&1)"
    testframework::assert_command "grep -q 'report=готово / done' <<< '${out}'" "cache_demo.sh demonstrates L1"
    testframework::assert_command "grep -q 'из L3 / from L3' <<< '${out}'" "cache_demo.sh demonstrates L3 promotion"
    testframework::assert_command "grep -q 'просрочено / expired' <<< '${out}'" "cache_demo.sh demonstrates TTL"
}


test_cli_codes_and_marker() {
    local rc=0
    export BS_CACHE_DIR="${T}/codes"
    "${BS_PROJECT_ROOT}/bs" cache put k v >/dev/null
    rc=0; "${BS_PROJECT_ROOT}/bs" cache get "bad key" 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "a bad key via the CLI is 2, not a masked miss"
    rc=0; "${BS_PROJECT_ROOT}/bs" cache get k extra 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "get refuses a second positional"
    rc=0; "${BS_PROJECT_ROOT}/bs" cache delete k extra 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "delete refuses extra arguments"
    rc=0; "${BS_PROJECT_ROOT}/bs" cache stats extra 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "stats refuses extra arguments"
    rc=0; "${BS_PROJECT_ROOT}/bs" cache get k --fp -x 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "--fp refuses a flag-looking value (use --fp=)"
    mkdir -p "${T}/foreign"
    rc=0; BS_CACHE_DIR="${T}/foreign" "${BS_PROJECT_ROOT}/bs" cache clear 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "clear refuses a directory without the .bs-cache marker"
    unset BS_CACHE_DIR
}

main() {
    T="$(mktemp -d)"
    testframework::section "Loaded via load / Загрузка через load"; test_loaded_via_load
    testframework::section "CLI cross-process / CLI между процессами"; test_cli_cross_process
    testframework::section "CLI flags and errors / Флаги и ошибки CLI"; test_cli_flags_and_errors
    testframework::section "CLI codes and marker / Коды CLI и маркер"; test_cli_codes_and_marker
    testframework::section "C backend / C-бэкенд"; test_c_backend
    testframework::section "Strict mode safety / Безопасность в set -e"; test_strict_mode_safety
    testframework::section "Example runs / Пример запускается"; test_example_runs
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
