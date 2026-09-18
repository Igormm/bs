#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testhwdbunit.sh — Unit tests for hw:: DB layer (lib/system/hw)
# tests/unit/testhwdbunit.sh — Модульные тесты слоя БД hw:: (lib/system/hw)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/system/hw"

test_universal_keys() {
    # Ключи, которые есть на любом Linux / Keys present on any Linux
    testframework::assert_command "hw::get mb.os.kernel | grep -q ." "mb.os.kernel present"
    testframework::assert_command "hw::get mb.os.arch | grep -q ." "mb.os.arch present"
    testframework::assert_command "hw::get mb.os.hostname | grep -q ." "mb.os.hostname present"
    testframework::assert_command "hw::get mb.cpu.name | grep -q ." "mb.cpu.name present"
    testframework::assert_command "hw::get mb.cpu.threads | grep -qE '^[1-9]'" "mb.cpu.threads positive"
    testframework::assert_command "hw::get mb.cpu.cores | grep -qE '^[1-9]'" "mb.cpu.cores positive"
    testframework::assert_command "hw::get mb.memory.total_mb | grep -qE '^[1-9]'" "mb.memory.total_mb positive"
    testframework::assert_command "hw::get mb.efi.mode | grep -qE '^(uefi|bios)$'" "mb.efi.mode is uefi or bios"
    testframework::assert_command "hw::get mb.tpm.present | grep -qE '^(yes|no)$'" "mb.tpm.present boolean"

    # Значения совпадают с системой / Values match the system
    local threads
    threads="$(hw::get mb.cpu.threads)"
    testframework::assert_equal "$(nproc)" "${threads}" "mb.cpu.threads matches nproc"

    # Дефолт / Default
    testframework::assert_equal "fallback" "$(hw::get mb.not.existing fallback)" "hw::get returns default"
}

test_navigation() {
    # ls / cd / pwd / count / find / dump
    testframework::assert_command "hw::ls mb | grep -qx cpu" "hw::ls mb lists cpu group"
    testframework::assert_command "hw::ls mb | grep -qx memory" "hw::ls mb lists memory group"
    testframework::assert_command "hw::ls mb.cpu | grep -qx threads" "hw::ls mb.cpu lists threads"

    hw::cd mb.cpu
    testframework::assert_equal "mb.cpu" "$(hw::pwd)" "hw::cd changes path"
    testframework::assert_command "hw::get name | grep -q ." "relative get works after cd"
    testframework::assert_command "hw::ls | grep -qx flags" "hw::ls without arg lists cwd children"

    hw::cd /
    testframework::assert_equal "mb" "$(hw::pwd)" "hw::cd / resets to root"
    testframework::assert_false "hw::cd mb.not_a_node" "hw::cd rejects unknown node"

    testframework::assert_command "hw::find kernel | grep -q mb.os.kernel" "hw::find by substring"
    testframework::assert_command "hw::count mb | grep -qE '^[1-9]'" "hw::count positive"
    testframework::assert_command "hw::dump mb.os | grep -q 'mb.os.kernel'" "hw::dump prints key=value"
}

test_dmi_mock() {
    # Подмена DMI (тестовый хук HW_DMI_PATH) / Fake DMI via the hook
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    printf 'FAKE_VENDOR\n' > "${tmp_dir}/bios_vendor"
    printf '1.0\n' > "${tmp_dir}/bios_version"
    printf '2026-01-01\n' > "${tmp_dir}/bios_date"

    hw::reset
    HW_DMI_PATH="${tmp_dir}" hw::get mb.bios.vendor
    testframework::assert_equal "FAKE_VENDOR" "$(HW_DMI_PATH="${tmp_dir}" hw::get mb.bios.vendor)" "hw::get honors HW_DMI_PATH hook"

    hw::reset
    rm -rf "${tmp_dir}"
}

test_flags_loop_ifs() {
    # Регрессия: цикл флагов не зависит от IFS вызывающего (без пробела)
    # Regression: the flags loop does not depend on the caller's IFS (no space)
    local saved_ifs="${IFS}"
    local flags first_flag count
    flags="$(awk -F': ' '/^flags/ {print $2; exit}' /proc/cpuinfo)"
    first_flag="${flags%% *}"

    IFS=$'\n\t'
    hw::reset
    hw::__build
    IFS="${saved_ifs}"

    testframework::assert_equal "1" "$(hw::get "mb.cpu.flags.${first_flag}")" \
        "flags yield separate mb.cpu.flags.<flag> keys under IFS newline+tab"
    testframework::assert_false "hw::get 'mb.cpu.flags.${flags}'" \
        "no space-joined garbage key under IFS newline+tab"
    count="$(hw::count mb.cpu.flags)"
    testframework::assert_true "${count} -gt 10" "separate flag keys count > 10 (got ${count})"
}

test_os_release_missing() {
    # Регрессия: отсутствие /etc/os-release не убивает сборку под set -e
    # Regression: a missing /etc/os-release must not kill the build under set -e
    local val rc=0
    val="$(utils::attempt awk -F= '/^NAME=/{gsub(/"/,"",$2); print $2}' /etc/os-release-does-not-exist)" || rc=$?
    testframework::assert_equal "0" "${rc}" "os-release read returns 0 when file is missing"
    testframework::assert_equal "" "${val}" "os-release read yields empty value when file is missing"
}

main() {
    print_header "HW DB Unit Tests / Модульные тесты БД hw"

    testframework::init

    if [[ ! -d /proc/self ]] || ! is::file /proc/cpuinfo; then
        echo "  SKIP: not a Linux procfs environment"
        testframework::summary
        return 0
    fi

    testframework::section "Universal keys / Универсальные ключи"
    test_universal_keys

    testframework::section "Navigation / Навигация"
    test_navigation

    testframework::section "DMI hook / Хук DMI"
    test_dmi_mock

    testframework::section "Regression: IFS / os-release / Регрессия: IFS и os-release"
    test_flags_loop_ifs
    test_os_release_missing

    testframework::summary
}

main "$@"