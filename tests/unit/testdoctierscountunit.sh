#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testdoctierscountunit.sh — tier counts in the docs match the @shell labels of core/
# tests/unit/testdoctierscountunit.sh — счётчики ярусов в документации совпадают с метками @shell в core/
#
# The numbers "12 of 15 core/ files are posix, 3 are bash4" are written by hand in README, AGENTS,
# Getting Started, architecture, portability, shell-portability and the skills. After every
# conversion of a file they went stale. This test computes the truth from the `# @shell` label of
# every core/*.sh (first 14 lines, as check_posix_tier.sh reads it) and fails on every sentence in
# the docs that states a different number. CHANGELOG.md is history and is not checked.
# Числа «12 из 15 файлов core/ — posix, 3 — bash4» вписаны вручную в README, AGENTS, Getting Started,
# architecture, portability, shell-portability и навыки; после каждого перевода файла они устаревали.
# Тест считает правду по метке `# @shell` каждого core/*.sh и падает на каждой фразе в документации
# с другим числом. CHANGELOG.md — история, его не проверяем.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

POSIX=0
BASH4=0
TOTAL=0
MATCHES=0

count_tiers() {
    local f
    while IFS= read -r f; do
        TOTAL=$((TOTAL + 1))
        if head -n 14 "${f}" | grep -q '^# @shell posix'; then
            POSIX=$((POSIX + 1))
        else
            BASH4=$((BASH4 + 1))
        fi
    done < <(find "${BS_PROJECT_ROOT}/core" -maxdepth 1 -name '*.sh' | sort)
}

# check_file <file> — prints one line per wrong statement (nothing when all are right)
check_file() {
    local -r file="$1"
    local text hit num total want
    text="$(tr '\n' ' ' < "${file}" | tr -s ' ')"

    # posix count: "the 12 `@shell posix`", "exception is 12 small `@shell posix`", "12 файлов ядра ...",
    # "Already done: 12 of the 15", "готово 12 из 15" / posix-число
    local -a posix_res=(
        'the [0-9]+ `@shell posix`'
        'Only the [0-9]+ `@shell posix`'
        'exception is [0-9]+ (small )?`@shell posix`'
        '[0-9]+ small `@shell posix`'
        'Исключение — [0-9]+ (небольших )?файлов'
        '[0-9]+ файлов ядра с меткой'
        '[0-9]+ файлов ядра `@shell posix`'
        '[0-9]+ небольших файлов'
        '[0-9]+ небольших `@shell posix`'
        '[0-9]+ файлов ядра и пролог'
        '[0-9]+ файлов ядра от bash'
        '[0-9]+ kernel files and the prologue'
        '[0-9]+ kernel files labelled'
        '(Already done|State): [0-9]+ of the 15'
        '(Уже готово|готово) [0-9]+ из 15'
        'only [0-9]+ small `@shell posix`'
        'от bash не зависят только [0-9]+'
    )
    for hit in "${posix_res[@]}"; do
        while IFS= read -r num; do
            [[ -n "${num}" ]] || continue
            if [[ "${num}" == "${POSIX}" ]]; then echo "ok"; else printf 'bad: %s: "%s" — expected %s\n' "${file#"${BS_PROJECT_ROOT}"/}" "$(grep -oE "${hit}" <<< "${text}" | head -n 1)" "${POSIX}"; fi
        done < <(grep -oE "${hit}" <<< "${text}" | grep -oE '[0-9]+' | head -n 1)
    done

    # bash count and total: "and 3 of the 15", "и 3 из 15"
    while IFS= read -r hit; do
        [[ -n "${hit}" ]] || continue
        num="$(grep -oE '[0-9]+' <<< "${hit}" | sed -n 1p)"
        total="$(grep -oE '[0-9]+' <<< "${hit}" | sed -n 2p)"
        if [[ "${num}" != "${BASH4}" || "${total}" != "${TOTAL}" ]]; then
            printf 'bad: %s: "%s" — expected %s of %s\n' "${file#"${BS_PROJECT_ROOT}"/}" "${hit}" "${BASH4}" "${TOTAL}"
        else
            echo "ok"
        fi
    done < <(grep -oE '(and|и) [0-9]+ (of the|из) [0-9]+ ' <<< "${text}")

    # tier table rows of architecture.md: "| `posix` (12) | `prereq`", "| `bash4` (3) | `lang`"
    while IFS= read -r hit; do
        [[ -n "${hit}" ]] || continue
        num="$(sed -E 's/.*\(([0-9]+)\).*/\1/' <<< "${hit}")"
        case "${hit}" in
            *posix*) want="${POSIX}" ;;
            *) want="${BASH4}" ;;
        esac
        if [[ "${num}" == "${want}" ]]; then echo "ok"; else printf 'bad: %s: "%s" — expected %s\n' "${file#"${BS_PROJECT_ROOT}"/}" "${hit}" "${want}"; fi
    done < <(grep -oE '`(posix|bash4)` \([0-9]+\) \| `(prereq|lang)`' <<< "${text}")
}

test_counts_match_labels() {
    local f out
    local -a files=()
    while IFS= read -r f; do files+=("${f}"); done < <(
        cd "${BS_PROJECT_ROOT}" && {
            printf '%s\n' README.md AGENTS.md
            find documentation .agents -name '*.md' -not -path '.agents/skills/bs-kernel-code/*' | sort
        } | sed "s#^#${BS_PROJECT_ROOT}/#")
    for f in "${files[@]}"; do
        [[ -f "${f}" ]] || continue
        out="$(check_file "${f}")"
        MATCHES=$((MATCHES + $(grep -c '^ok$' <<< "${out}" || true)))
        testframework::assert_equal "" "$(grep '^bad:' <<< "${out}" || true)" "tier counts in ${f#"${BS_PROJECT_ROOT}"/}" || true
    done
}

test_checker_is_not_blind() {
    # the patterns must find the statements; a wrong regex would make the test pass on nothing
    testframework::assert_true "${MATCHES} -ge 15" "the checker found ${MATCHES} tier statements in the docs (>= 15)" || true
    testframework::assert_true "${TOTAL} -ge 15 && $((POSIX + BASH4)) -eq ${TOTAL}" "core/ has ${TOTAL} files: ${POSIX} posix + ${BASH4} bash4" || true
}

test_negative_control() {
    # a wrong number must be caught: feed a fake doc through the same function
    local tmp out
    tmp="$(mktemp)"
    printf 'The exception is 99 small `@shell posix` kernel files, and 98 of the 15 core files.\n' > "${tmp}"
    out="$(check_file "${tmp}" | grep -c '^bad:' || true)"
    rm -f "${tmp}"
    testframework::assert_true "${out} -ge 2" "the wrong numbers are reported (${out})" || true
}

main() {
    count_tiers
    testframework::section "Counts in the docs / Счётчики в документации"; test_counts_match_labels
    testframework::section "The checker itself / Сам проверяющий"; test_checker_is_not_blind; test_negative_control
    testframework::summary
}

main "$@"
