#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testcacheportableunit.sh — core/cache.sh (three-level cache) under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testcacheportableunit.sh — core/cache.sh (трёхуровневый кеш) под dash, ash, ksh, mksh, zsh и bash
#
# core/cache.sh is "@shell posix": the manifest, L1/L2/L3, TTL, LRU and the backend probe must
# give the same answers in every shell. L3 backends: sqlite3 when installed, else files; the
# C backend is exercised by testcacheunit.sh when a compiler is available.
# core/cache.sh — "@shell posix": манифест, L1/L2/L3, TTL, LRU и проба бэкендов обязаны давать
# одинаковые ответы в любой оболочке. L3: sqlite3 при наличии, иначе файлы; C-бэкенд проверяет
# testcacheunit.sh при наличии компилятора.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly CACHE_SH="${BS_PROJECT_ROOT}/core/cache.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — слой, prereq, data и cache подключены; snippet сам создаёт каталог
# probe <shell> <snippet> — the layer, prereq, data and cache are sourced; the snippet makes its own dir
probe() {
    local -r sh_bin="$1" snippet="$2"
    local f
    : > "${T}/probe.sh"
    for f in bootstrap/shell.sh core/prereq.sh core/data.sh core/cache.sh; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf 'D=$(mktemp -d)\nexport BS_CACHE_DIR="$D/c"\n%s\nrm -rf "$D"\n' "${snippet}" >> "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${CACHE_SH}'" "cache.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh --severity=error '${CACHE_SH}'" "shellcheck -s sh has no errors for core/cache.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${CACHE_SH}'" "core/cache.sh is declared @shell posix" || true
}

test_l1_and_codes() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "hello world" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 "hello world"; bs_cache_get k1 fp1')" "${sh_name}: put + get L1"
        eq "via-var" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 via-var; bs_cache_get k1 fp1 v; printf "%s" "$v"')" "${sh_name}: get into a variable"
        eq "rc=1 rc=1" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 x; bs_cache_get k1 other 2>/dev/null; printf "rc=%s " "$?"; bs_cache_get nope fp1 2>/dev/null; printf "rc=%s" "$?"')" "${sh_name}: fp mismatch and missing are misses"
        eq "rc=2 rc=2 rc=2" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put "bad key" fp1 x 2>/dev/null; printf "rc=%s " "$?"; bs_cache_put k1 "bad fp" x 2>/dev/null; printf "rc=%s " "$?"; bs_cache_put k1 fp1 x abc 2>/dev/null; printf "rc=%s" "$?"')" "${sh_name}: bad key/fp/ttl are 2"
        eq "ok" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 x 08 && bs_cache_get k1 fp1 >/dev/null && printf ok')" "${sh_name}: ttl with leading zeros is accepted"
        eq "it's * Привет" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 "it'"'"'s * Привет"; bs_cache_get k1 fp1')" "${sh_name}: hard values survive"
        eq "a
b" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 "a
b"; bs_cache_get k1 fp1')" "${sh_name}: inner newlines survive"
        eq "rc=0 rc=1" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 x; bs_cache_has k1 fp1; printf "rc=%s " "$?"; bs_cache_delete k1; bs_cache_has k1 fp1; printf "rc=%s" "$?"')" "${sh_name}: has and delete"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 x; bs_cache_clear; bs_cache_get k1 fp1 2>/dev/null; echo rc=$?')" "${sh_name}: clear empties every level"
    done < <(testframework::posix_shells)
}

test_manifest_and_stats() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "yes" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put mykey myfp x; bs_cache_list | grep -q "key=mykey fp=myfp" && printf yes')" "${sh_name}: the manifest is readable key=value"
        eq "yes" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 x; bs_cache_stats | grep -q "^l2=1" && bs_cache_stats | grep -q "^bytes=1" && printf yes')" "${sh_name}: stats count entries and bytes"
        eq "yes" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 x; bs_cache_get k1 fp1 >/dev/null; bs_cache_list | grep -q "hits=1" && printf yes')" "${sh_name}: hits are recorded in the manifest"
        eq "yes" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_stats | grep -qE "^l3=(sqlite|cstore|files)$" && printf yes')" "${sh_name}: the L3 backend is probed"
    done < <(testframework::posix_shells)
}

test_l2_l3_promotion() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "L2-hit" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 L2-hit; bs_map_clear cacheV; bs_map_clear cacheF; bs_cache_init; bs_cache_get k1 fp1')" "${sh_name}: a fresh init reads L2 (survives the process state)"
        eq "L3-hit
 promoted" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 L3-hit; rm -f "$BS_CACHE_DIR"/v/*; bs_map_clear cacheV; bs_map_clear cacheF; bs_cache_init; bs_cache_get k1 fp1; ls "$BS_CACHE_DIR/v" | grep -q . && printf " promoted"')" "${sh_name}: L3 hit promotes back to L2"
        eq "files-hit" "$(probe "${sh_bin}" 'BS_CACHE_L3=files; bs_cache_init; bs_cache_put k1 fp1 files-hit; rm -f "$BS_CACHE_DIR"/v/*; bs_map_clear cacheV; bs_map_clear cacheF; bs_cache_init; bs_cache_get k1 fp1')" "${sh_name}: the files L3 backend works"
        if utils::has sqlite3; then
            eq "sqlite-hit" "$(probe "${sh_bin}" 'BS_CACHE_L3=sqlite; bs_cache_init; bs_cache_put k1 fp1 sqlite-hit; rm -f "$BS_CACHE_DIR"/v/*; bs_map_clear cacheV; bs_map_clear cacheF; bs_cache_init; bs_cache_get k1 fp1')" "${sh_name}: the sqlite L3 backend works"
        fi
    done < <(testframework::posix_shells)
}

test_ttl_and_prune() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 x 1; sleep 2; bs_cache_get k1 fp1 2>/dev/null; echo rc=$?')" "${sh_name}: an expired ttl is a miss"
        eq "1" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 x 1; sleep 2; bs_cache_prune')" "${sh_name}: prune removes the expired"
        eq "still" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 still; BS_CACHE_L2_BYTES=1 bs_cache_prune >/dev/null; bs_cache_get k1 fp1')" "${sh_name}: LRU eviction keeps the value in L3"
        eq "yes" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k1 fp1 0123456789; BS_CACHE_L2_BYTES=1 bs_cache_prune >/dev/null; bs_cache_list | grep -q "level=3" && printf yes')" "${sh_name}: the evicted entry is level=3 in the manifest"
    done < <(testframework::posix_shells)
}

test_fingerprint() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "differs" "$(probe "${sh_bin}" 'printf one > "$D/f"; a=$(bs_cache_fp_files "$D/f"); printf two > "$D/f"; b=$(bs_cache_fp_files "$D/f"); [ "$a" != "$b" ] && printf differs')" "${sh_name}: fp_files changes with the content"
        eq "same" "$(probe "${sh_bin}" 'printf one > "$D/f"; a=$(bs_cache_fp_files "$D/f"); b=$(bs_cache_fp_files "$D/f"); [ "$a" = "$b" ] && printf same')" "${sh_name}: fp_files is stable"
    done < <(testframework::posix_shells)
}


test_review_regressions() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "FIRST" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put ab c FIRST; bs_cache_put a bc SECOND; bs_map_clear cacheV; bs_map_clear cacheF; bs_cache_init; bs_cache_get ab c')" "${sh_name}: key|fp gluing does not collide (ab+c vs a+bc)"
        eq "ok
rc=1" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put good fp1 ok; printf "id=../../etc/passwd key=evil fp=f level=2 size=1 created=1 ttl=0 hits=0 used=1\n" >> "$BS_CACHE_DIR/manifest"; printf "garbage line\n" >> "$BS_CACHE_DIR/manifest"; printf "id=e9 key=k2 fp=f2 level=2\n" >> "$BS_CACHE_DIR/manifest"; bs_cache_init; bs_cache_get good fp1; bs_cache_get evil f 2>/dev/null; printf "rc=%s" "$?"')" "${sh_name}: garbage and traversal manifest lines are skipped"
        eq "rc=3 alive" "$(probe "${sh_bin}" 'bs_cache_init; chmod 500 "$BS_CACHE_DIR"; bs_cache_put k fp1 x 2>/dev/null; printf "rc=%s " "$?"; chmod 700 "$BS_CACHE_DIR"; printf alive')" "${sh_name}: a read-only cache dir gives code 3, not a dead shell"
        eq "bytes=12" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k fp1 "Привет"; bs_cache_stats | grep "^bytes="')" "${sh_name}: size is bytes in every shell (Cyrillic)"
        eq "level=3" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k fp1 x; rm -f "$BS_CACHE_DIR"/v/*; bs_cache_get k fp1 >/dev/null; bs_cache_list | grep -o "level=[0-9]"')" "${sh_name}: an L1 hit without the L2 file keeps level=3 in the manifest"
        eq "differs" "$(probe "${sh_bin}" 'printf one > "$D/f"; chmod 000 "$D/f"; a=$(bs_cache_fp_files "$D/f"); printf two > "$D/g"; chmod 000 "$D/g"; b=$(bs_cache_fp_files "$D/g"); chmod 600 "$D/f" "$D/g"; [ "$a" != "$b" ] && printf differs')" "${sh_name}: unreadable files get distinct fingerprints"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_cache_init; bs_cache_put k fp1 x 9999999999 2>/dev/null; echo rc=$?')" "${sh_name}: an oversized ttl is refused (32-bit mksh)"
    done < <(testframework::posix_shells)
}

main() {
    T="$(mktemp -d)"
    mkdir -p "${T}/h"
    testframework::section "Parses and lints / Разбор и линт"; test_parses_and_lints
    testframework::section "L1 and codes / L1 и коды"; test_l1_and_codes
    testframework::section "Manifest and stats / Манифест и статистика"; test_manifest_and_stats
    testframework::section "L2/L3 and promotion / L2/L3 и продвижение"; test_l2_l3_promotion
    testframework::section "TTL and prune / TTL и prune"; test_ttl_and_prune
    testframework::section "Fingerprint / Отпечаток"; test_fingerprint
    testframework::section "Review regressions / Регрессии обзора"; test_review_regressions
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
