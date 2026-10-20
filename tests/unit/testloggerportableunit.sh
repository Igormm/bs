#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testloggerportableunit.sh — core/logger.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testloggerportableunit.sh — core/logger.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/logger.sh is "@shell posix": levels, formats, colours and the helpers must give the same
# answers in every shell. Timestamps are off (BS_LOG_TIMESTAMP=false) so the output is exact.
# core/logger.sh — "@shell posix": уровни, форматы, цвета и помощники обязаны давать одинаковые
# ответы в любой оболочке. Метки времени выключены, чтобы вывод был точным.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly LOGGER_SH="${BS_PROJECT_ROOT}/core/logger.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <env> <snippet> — слой, prereq, const и logger подключены, затем snippet (stdout+stderr)
probe() {
    local -r sh_bin="$1" envs="$2" snippet="$3"
    local f
    : > "${T}/probe.sh"
    for f in bootstrap/shell.sh core/prereq.sh core/const.sh core/logger.sh; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "${snippet}" >> "${T}/probe.sh"
    # shellcheck disable=SC2086  # envs — список VAR=значение, делится по словам намеренно / a VAR=value list, split on purpose
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" BS_LOG_TIMESTAMP=false ${envs} "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${LOGGER_SH}'" "logger.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${LOGGER_SH}'" "shellcheck -s sh is clean for core/logger.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${LOGGER_SH}'" "core/logger.sh is declared @shell posix" || true
}

test_behaviour() {
    local sh_bin sh_name out esc
    esc="$(printf '\033')"
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "[INFO ] hello world" "$(probe "${sh_bin}" '' 'bs_log_info hello world')" "${sh_name}: text format, words joined by a space"
        eq "[WARN ] careful" "$(probe "${sh_bin}" '' 'bs_log_warn careful')" "${sh_name}: warn goes to stderr and is printed"
        eq "" "$(probe "${sh_bin}" 'BS_LOG_LEVEL=ERROR' 'bs_log_info hidden; bs_log_warn hidden')" "${sh_name}: levels below the configured one are hidden"
        eq "[ERROR] shown" "$(probe "${sh_bin}" 'BS_LOG_LEVEL=ERROR' 'bs_log_error shown')" "${sh_name}: the configured level is shown"
        eq "" "$(probe "${sh_bin}" 'BS_LOG_LEVEL=NONE' 'bs_log_error x; bs_log_fatal y')" "${sh_name}: NONE hides everything"
        eq "[INFO ] low" "$(probe "${sh_bin}" 'BS_LOG_LEVEL=info' 'bs_log_info low')" "${sh_name}: the level name is case-insensitive"
        eq "[INFO ] | s" "$(probe "${sh_bin}" 'BS_LOG_FORMAT=structured' 'bs_log_info s' | sed 's/\[INFO \] s/[INFO ] | s/')" "${sh_name}: structured format has no timestamp when it is off"
        eq '{"level":"INFO","message":"a\"b\\c\nd"}' "$(probe "${sh_bin}" 'BS_LOG_FORMAT=json' 'bs_log_info "$(printf "a\"b\\\\c\nd")"')" "${sh_name}: json escapes quote, backslash, newline"
        eq "${esc}[34mINFO ${esc}[0m c" "$(probe "${sh_bin}" 'BS_LOG_COLOR=always' 'bs_log_info c')" "${sh_name}: forced colour (blue INFO)"
        eq "${esc}[31m${esc}[1mERROR${esc}[0m e" "$(probe "${sh_bin}" 'BS_LOG_COLOR=always' 'bs_log_error e')" "${sh_name}: forced colour (bold red ERROR)"
        eq "[INFO ] nc" "$(probe "${sh_bin}" 'BS_LOG_COLOR=always NO_COLOR=1' 'bs_log_info nc')" "${sh_name}: NO_COLOR wins"
        eq "rc=1" "$(probe "${sh_bin}" '' 'bs_log_fatal f >/dev/null 2>&1; echo rc=$?')" "${sh_name}: bs_log_fatal returns E_ERROR"
        eq "20 30 20 1000" "$(probe "${sh_bin}" '' 'echo $(bs_log_level_to_number info) $(bs_log_level_to_number Warn) $(bs_log_level_to_number bogus) $(bs_log_level_to_number NONE)')" "${sh_name}: level numbers"
        out="$(probe "${sh_bin}" '' 'bs_log_header Hi' | tr '\n' '|')"
        eq "[INFO ] ╭────╮|[INFO ] │ Hi │|[INFO ] ╰────╯|" "${out}" "${sh_name}: header box"
        out="$(probe "${sh_bin}" '' 'bs_log_header Title =' | tr '\n' '|')"
        eq "[INFO ] |[INFO ] Title|[INFO ] =====|[INFO ] |" "${out}" "${sh_name}: header line"
        out="$(probe "${sh_bin}" '' 'bs_log_header Привет' | tr '\n' '|')"
        eq "[INFO ] ╭────────╮|[INFO ] │ Привет │|[INFO ] ╰────────╯|" "${out}" "${sh_name}: header box counts UTF-8 characters, not bytes"
        out="$(probe "${sh_bin}" '' 'bs_log_header Привет =' | tr '\n' '|')"
        eq "[INFO ] |[INFO ] Привет|[INFO ] ======|[INFO ] |" "${out}" "${sh_name}: header line counts UTF-8 characters, not bytes"
        out="$(probe "${sh_bin}" '' 'bs_log_list a "b c"; bs_log_table r1 "r 2"' | tr '\n' '|')"
        eq "[INFO ]   * a|[INFO ]   * b c|[INFO ]   r1|[INFO ]   r 2|" "${out}" "${sh_name}: list and table"
        out="$(probe "${sh_bin}" '' 'bs_log_progress 5 10 10; bs_log_progress 10 10 10' | tr '\r\n' '/|')"
        eq "/  [█████     ] 50%/  [██████████] 100%|" "${out}" "${sh_name}: progress bar"
        eq "rc=1" "$(probe "${sh_bin}" '' 'bs_log_progress 1 0 10 >/dev/null 2>&1; echo rc=$?')" "${sh_name}: progress with max 0 returns 1"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "[INFO ] x" "$(probe "${sh_bin}" '' 'log::info x')" "${sh_name}: log::info is an alias of bs_log_info"
        eq "[WARN ] y" "$(probe "${sh_bin}" '' 'log::warn y')" "${sh_name}: log::warn is an alias of bs_log_warn"
        eq "20" "$(probe "${sh_bin}" '' 'log::__level_to_number info')" "${sh_name}: log::__level_to_number is an alias"
    done
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
