#!/usr/bin/env bs
# shellcheck shell=bash
# tests/integration/testinstall.sh — Installer integration tests
# tests/integration/testinstall.sh — Интеграционные тесты установщика
#
# Безопасный прогон: каждая установка выполняется в изолированном HOME
# (mktemp) с переопределёнными PREFIX/BIN_DIR/LIB_DIR. Ничего не пишется
# в реальный ~/.local или /usr/local. Root не требуется.
#
# Safe run: every install runs in an isolated HOME (mktemp) with overridden
# PREFIX/BIN_DIR/LIB_DIR. Nothing touches the real ~/.local or /usr/local.
# No root required.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly INSTALLER="${BS_PROJECT_ROOT}/install.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

readonly TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bs_install_test.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

# Изолированный HOME для одного сценария / Isolated HOME for one scenario
mk_isolated_home() {
    mktemp -d "${TMP_ROOT}/home.XXXXXX"
}

# Запуск установщика в изолированном HOME; вывод (stdout+stderr) в stdout
run_installer() {
    local isolated_home="$1"
    shift
    env HOME="${isolated_home}" bash "${INSTALLER}" "$@" 2>&1
}

# Установка по умолчанию (local-режим): пути в ~/.local изолированного HOME
test_help_flag() {
    local iso rc=0 out
    iso="$(mk_isolated_home)"
    out="$(run_installer "${iso}" --help)" || rc=$?
    testframework::assert_equal "0" "${rc}" "install.sh --help exits 0"
    testframework::assert_true "'${out}' =~ BS\ installer" "help output mentions install command"
}

test_unknown_flag() {
    local iso rc=0 out
    iso="$(mk_isolated_home)"
    out="$(run_installer "${iso}" --bogus)" || rc=$?
    testframework::assert_equal "1" "${rc}" "unknown flag exits 1"
    testframework::assert_true "'${out}' =~ Неизвестный\ аргумент" "unknown flag error message"
}

test_local_install() {
    local iso rc=0 out
    iso="$(mk_isolated_home)"
    out="$(run_installer "${iso}" --local)" || rc=$?
    testframework::assert_equal "0" "${rc}" "local install exits 0"
    testframework::assert_true "'${out}' =~ Готово" "install prints completion message"

    local bin lib
    bin="${iso}/.local/bin/bs"
    lib="${iso}/.local/lib/bs"

    testframework::assert_file_exists "${bin}" "wrapper created at ~/.local/bin/bs"
    testframework::assert_command "test -x '${bin}'" "wrapper is executable"

    testframework::assert_file_exists "${lib}/bs"               "main launcher copied"
    testframework::assert_file_exists "${lib}/bootstrap/init.sh" "bootstrap/init.sh copied"
    testframework::assert_file_exists "${lib}/bootstrap/loader.sh" "bootstrap/loader.sh copied"
    testframework::assert_file_exists "${lib}/core/utils.sh"     "core/utils.sh copied"
    testframework::assert_command "test -d '${lib}/lib/io'"      "lib/io directory copied"

    if grep -q 'export BS_ROOT=' "${bin}"; then
        testframework::assert_true "true" "wrapper exports BS_ROOT"
    else
        testframework::assert_true "false" "wrapper exports BS_ROOT"
    fi

    local version_out
    version_out="$(env HOME="${iso}" "${bin}" version)"
    testframework::assert_equal "BS Framework version: 0.4.0" "${version_out}" "installed bs version works"

    local list_out
    list_out="$(env HOME="${iso}" "${bin}" list)"
    testframework::assert_true "'${list_out}' =~ core/utils\.sh" "installed bs list sees core modules"

    local rc_doctor=0
    env HOME="${iso}" "${bin}" doctor >/dev/null 2>&1 || rc_doctor=$?
    testframework::assert_equal "0" "${rc_doctor}" "installed bs doctor passes"

    if grep -q '\.local/bin' "${iso}/.bashrc" 2>/dev/null; then
        testframework::assert_true "true" "local install updates isolated .bashrc PATH"
    else
        testframework::assert_true "false" "local install updates isolated .bashrc PATH"
    fi
}

test_reinstall_blocked() {
    local iso rc=0 out
    iso="$(mk_isolated_home)"
    run_installer "${iso}" --local >/dev/null 2>&1 || true

    out="$(run_installer "${iso}" --local)" || rc=$?
    testframework::assert_equal "1" "${rc}" "second install while present exits 1"
    testframework::assert_true "'${out}' =~ Предупреждение" "reinstall prints warning"
}

test_custom_paths() {
    local iso prefix rc=0 out
    iso="$(mk_isolated_home)"
    prefix="${TMP_ROOT}/custom.$$"

    out="$(env HOME="${iso}" PREFIX="${prefix}" BIN_DIR="${prefix}/bin" LIB_DIR="${prefix}/lib" \
           bash "${INSTALLER}" --local install)" || rc=$?
    testframework::assert_equal "0" "${rc}" "install with custom PREFIX/BIN_DIR/LIB_DIR exits 0"

    testframework::assert_file_exists "${prefix}/bin/bs"      "wrapper lands in custom BIN_DIR"
    testframework::assert_command "test -d '${prefix}/lib/bs/core'" "core lands in custom LIB_DIR"
    testframework::assert_file_exists "${prefix}/lib/bs/core/utils.sh" "core module file lands in custom LIB_DIR"

    rc=0
    out="$(env HOME="${iso}" PREFIX="${prefix}" BIN_DIR="${prefix}/bin" LIB_DIR="${prefix}/lib" \
           bash "${INSTALLER}" --local uninstall)" || rc=$?
    testframework::assert_equal "0" "${rc}" "uninstall with custom paths exits 0"

    if [[ -e "${prefix}/bin/bs" || -d "${prefix}/lib/bs" ]]; then
        testframework::assert_true "false" "uninstall removes custom BIN/LIB"
    else
        testframework::assert_true "true" "uninstall removes custom BIN/LIB"
    fi
}

test_uninstall() {
    local iso rc=0 out
    iso="$(mk_isolated_home)"
    run_installer "${iso}" --local >/dev/null 2>&1 || true

    out="$(run_installer "${iso}" --local uninstall)" || rc=$?
    testframework::assert_equal "0" "${rc}" "local uninstall exits 0"

    if [[ -e "${iso}/.local/bin/bs" || -d "${iso}/.local/lib/bs" ]]; then
        testframework::assert_true "false" "uninstall removes wrapper and libs"
    else
        testframework::assert_true "true" "uninstall removes wrapper and libs"
    fi

    local count
    count="$(grep -c '\.local/bin' "${iso}/.bashrc" 2>/dev/null || true)"
    testframework::assert_equal "0" "${count}" "uninstall removes installer PATH line from .bashrc"

    rc=0
    out="$(run_installer "${iso}" --local uninstall)" || rc=$?
    testframework::assert_equal "0" "${rc}" "second uninstall is graceful"
}

test_path_flag() {
    local iso rc=0 out
    iso="$(mk_isolated_home)"
    out="$(run_installer "${iso}" --local --path)" || rc=$?
    testframework::assert_equal "0" "${rc}" "--path exits 0"

    local hint_found=1
    grep -q 'export PATH=' <<< "${out}" && hint_found=0 || true
    testframework::assert_equal "0" "${hint_found}" "--path prints PATH snippet"
}

test_update_path_flag() {
    local iso rc=0 out
    iso="$(mk_isolated_home)"

    out="$(run_installer "${iso}" --local --update-path)" || rc=$?
    testframework::assert_equal "0" "${rc}" "--update-path exits 0"

    local count
    count="$(grep -c '\.local/bin' "${iso}/.bashrc" 2>/dev/null || true)"
    testframework::assert_equal "1" "${count}" "update-path added PATH line once"

    rc=0
    out="$(run_installer "${iso}" --local --update-path)" || rc=$?
    testframework::assert_equal "0" "${rc}" "--update-path is idempotent"

    count="$(grep -c '\.local/bin' "${iso}/.bashrc" 2>/dev/null || true)"
    testframework::assert_equal "1" "${count}" "second update-path does not duplicate line"
}

test_uninstall_keeps_user_edits() {
    local iso rc=0
    iso="$(mk_isolated_home)"
    run_installer "${iso}" --local >/dev/null 2>&1 || true

    printf 'PATH="$HOME/.local/bin/manual:$PATH"\n' >> "${iso}/.bashrc"

    run_installer "${iso}" --local uninstall >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "uninstall exits 0 with user edits present"

    if grep -q 'manual' "${iso}/.bashrc"; then
        testframework::assert_true "true" "user PATH edits survive uninstall"
    else
        testframework::assert_true "false" "user PATH edits survive uninstall"
    fi
}

test_system_mode_requires_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        printf "  ⊘ Skipping system-mode root check: running as root\n"
        return 0
    fi

    local iso rc=0 out
    iso="$(mk_isolated_home)"
    out="$(run_installer "${iso}")" || rc=$?
    testframework::assert_equal "1" "${rc}" "system install without root exits 1"
    testframework::assert_true "'${out}' =~ Нужны\ права\ root" "system mode asks for root"
}

main() {
    print_header "Installer Integration Tests / Интеграционные тесты установщика"

    testframework::init

    testframework::section "CLI basics / Базовый CLI"
    test_help_flag
    test_unknown_flag

    testframework::section "Local install / Локальная установка"
    test_local_install
    test_reinstall_blocked
    test_custom_paths

    testframework::section "Uninstall / Удаление"
    test_uninstall
    test_uninstall_keeps_user_edits

    testframework::section "PATH helpers / Настройка PATH"
    test_path_flag
    test_update_path_flag

    testframework::section "System mode / Системная установка"
    test_system_mode_requires_root

    testframework::summary
}

main "$@"