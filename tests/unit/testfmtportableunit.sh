#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testfmtportableunit.sh — core/fmt.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testfmtportableunit.sh — core/fmt.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/fmt.sh is "@shell posix": sizes and timestamps must give the same answers in every shell.
# core/fmt.sh — "@shell posix": размеры и метки времени обязаны давать одинаковые ответы в любой оболочке.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly SHELL_SH="${BS_PROJECT_ROOT}/bootstrap/shell.sh"
readonly PREREQ_SH="${BS_PROJECT_ROOT}/core/prereq.sh"
readonly FMT_SH="${BS_PROJECT_ROOT}/core/fmt.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — shell.sh, prereq.sh и fmt.sh подключены, затем snippet
probe() {
    local -r sh_bin="$1" snippet="$2"
    printf '. "%s"\n. "%s"\n. "%s"\n%s\n' "${SHELL_SH}" "${PREREQ_SH}" "${FMT_SH}" "${snippet}" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

# match <value> <digits-only?> — истина, если значение состоит только из цифр / true if the value is digits only
digits() { [[ "$1" =~ ^[0-9]+$ ]] && echo yes || echo no; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${FMT_SH}'" "fmt.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${FMT_SH}'" "shellcheck -s sh is clean for core/fmt.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${FMT_SH}'" "core/fmt.sh is declared @shell posix" || true
}

test_behaviour() {
    local sh_bin sh_name out f
    printf 'abcdefghijklmnop' > "${T}/data.txt"
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "1.5 MiB" "$(probe "${sh_bin}" 'bs_utils_human_size 1536000')" "${sh_name}: human_size of plain bytes"
        eq "12.0 MiB" "$(probe "${sh_bin}" 'bs_utils_human_size 12288K')" "${sh_name}: human_size of a K suffix"
        eq "3.0 GiB" "$(probe "${sh_bin}" 'bs_utils_human_size "3 GiB"')" "${sh_name}: human_size drops the inner space"
        eq "2.0 TiB" "$(probe "${sh_bin}" 'bs_utils_human_size 2TB')" "${sh_name}: human_size of TB"
        eq "512.0 B" "$(probe "${sh_bin}" 'bs_utils_human_size 512B')" "${sh_name}: human_size of B"
        eq "0.0 B" "$(probe "${sh_bin}" 'bs_utils_human_size 0')" "${sh_name}: human_size of 0"
        eq "abc" "$(probe "${sh_bin}" 'bs_utils_human_size abc')" "${sh_name}: a non-number is returned as is"
        eq "abcdefgh" "$(probe "${sh_bin}" "bs_utils_head_bytes '${T}/data.txt' 8")" "${sh_name}: head_bytes reads N bytes"
        eq "rc=1" "$(probe "${sh_bin}" "bs_utils_head_bytes '${T}/missing' 8; echo rc=\$?")" "${sh_name}: head_bytes of a missing file returns 1"
        eq "yes" "$(digits "$(probe "${sh_bin}" 'bs_utils_now_s')")" "${sh_name}: now_s is a number"
        out="$(probe "${sh_bin}" 'bs_utils_now_ms')"
        eq "yes" "$(digits "${out}")" "${sh_name}: now_ms is a number"
        eq "13" "${#out}" "${sh_name}: now_ms has 13 digits (milliseconds)"
        out="$(probe "${sh_bin}" 'bs_utils_stamp')"
        eq "yes" "$([[ "${out}" =~ ^[0-9]{8}_[0-9]{6}$ ]] && echo yes || echo no)" "${sh_name}: stamp is YYYYMMDD_HHMMSS"
        out="$(probe "${sh_bin}" 'bs_utils_log_stamp')"
        eq "yes" "$([[ "${out}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] && echo yes || echo no)" "${sh_name}: log_stamp is YYYY-MM-DD HH:MM:SS"
        out="$(probe "${sh_bin}" 'bs_utils_now_float')"
        eq "yes" "$([[ "${out}" =~ ^[0-9]+\.[0-9]+$ ]] && echo yes || echo no)" "${sh_name}: now_float has a fractional part"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "1.5 MiB" "$(probe "${sh_bin}" 'utils::human_size 1536000')" "${sh_name}: utils::human_size is an alias of bs_utils_human_size"
        eq "yes" "$(digits "$(probe "${sh_bin}" 'utils::now_s')")" "${sh_name}: utils::now_s is an alias of bs_utils_now_s"
    done
    eq "1.5 MiB" "$(utils::human_size 1536000)" "kernel: utils::human_size works"
    eq "yes" "$(digits "$(utils::now_ms)")" "kernel: utils::now_ms works"
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Behaviour in every shell / Поведение в каждой оболочке"; test_behaviour
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
