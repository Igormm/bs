#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testmsgportableunit.sh — core/msg.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testmsgportableunit.sh — core/msg.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/msg.sh is "@shell posix": messages go through the logger when it is loaded, to stderr otherwise.
# core/msg.sh — "@shell posix": сообщения идут через логгер, если он загружен, иначе в stderr.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly MODULE_SH="${BS_PROJECT_ROOT}/core/msg.sh"
# the files the probe sources, in dependency order / файлы, которые подключает проба, по порядку зависимостей
PROBE_FILES=(bootstrap/shell.sh core/prereq.sh core/msg.sh)

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
        testframework::assert_command "'${sh_bin}' -n '${MODULE_SH}'" "msg.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${MODULE_SH}'" "shellcheck -s sh is clean for core/msg.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${MODULE_SH}'" "core/msg.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${MODULE_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare| \\[\\[ |printf -v'" "no shell-specific constructs in core/msg.sh" || true
}

# probe with the logger loaded: const.sh (E_*) and logger.sh in front of msg.sh
probe_logger() {
    local -a saved=("${PROBE_FILES[@]}")
    PROBE_FILES=(bootstrap/shell.sh core/prereq.sh core/const.sh core/logger.sh core/msg.sh)
    probe "$1" "BS_LOG_TIMESTAMP=false; BS_LOG_COLOR=never; $2"
    PROBE_FILES=("${saved[@]}")
}

test_without_logger() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "ERROR: boom here" "$(probe "${sh_bin}" 'bs_msg_error boom here 2>&1')" "${sh_name}: error goes to stderr as ERROR: text"
        eq "WARN: careful" "$(probe "${sh_bin}" 'bs_msg_warn careful 2>&1')" "${sh_name}: warn goes to stderr"
        eq "INFO: hello" "$(probe "${sh_bin}" 'bs_msg_info hello 2>/dev/null')" "${sh_name}: info goes to stdout"
        eq "" "$(probe "${sh_bin}" 'bs_msg_info hello 2>&1 >/dev/null')" "${sh_name}: info prints nothing to stderr"
        eq "ERROR: a b" "$(probe "${sh_bin}" 'IFS=$(printf "\n\t"); bs_msg_error a b 2>&1')" "${sh_name}: words are joined with a space under the strict IFS"
        eq "ERROR: it's *" "$(probe "${sh_bin}" 'bs_msg_error "it'"'"'s" "*" 2>&1')" "${sh_name}: quotes and a star survive"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_msg_error x 2>/dev/null; echo rc=$?')" "${sh_name}: error itself returns 0"
        eq "ERROR: nope rc=1" "$(probe "${sh_bin}" 'bs_msg_fail nope 2>&1; echo rc=$?' | tr '\n' ' ' | sed 's/ $//')" "${sh_name}: fail returns 1 without const.sh"
        eq "ERROR: fn: bad arg rc=2" "$(probe "${sh_bin}" 'bs_msg_invalid fn bad arg 2>&1; echo rc=$?' | tr '\n' ' ' | sed 's/ $//')" "${sh_name}: invalid returns 2 and names the function"
        eq "STILL" "$(probe "${sh_bin}" 'bs_msg_fail x 2>/dev/null; echo STILL')" "${sh_name}: fail does not end the script"
    done < <(testframework::posix_shells)
}

test_with_logger() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "[ERROR] boom" "$(probe_logger "${sh_bin}" 'bs_msg_error boom 2>&1')" "${sh_name}: with the logger the message takes its format"
        eq "[INFO ] hi" "$(probe_logger "${sh_bin}" 'bs_msg_info hi 2>&1')" "${sh_name}: info through the logger"
        eq "[WARN ] w" "$(probe_logger "${sh_bin}" 'bs_msg_warn w 2>&1')" "${sh_name}: warn through the logger"
        eq "[ERROR] fn: bad rc=2" "$(probe_logger "${sh_bin}" 'bs_msg_invalid fn bad 2>&1; echo rc=$?' | tr '\n' ' ' | sed 's/ $//')" "${sh_name}: invalid through the logger returns E_INVALID"
    done < <(testframework::posix_shells)
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Without the logger / Без логгера"; test_without_logger
    testframework::section "With the logger / С логгером"; test_with_logger
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
