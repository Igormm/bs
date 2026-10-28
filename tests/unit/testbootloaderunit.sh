#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testbootloaderunit.sh — unit tests for lib/system/bootloader (grub_set/get, backup/restore, regenerate)
# tests/unit/testbootloaderunit.sh — модульные тесты lib/system/bootloader (grub_set/get, бэкап/откат, перегенерация)
#
# Всё в песочнице: BS_GRUB_CONFIG/BS_GRUB_CFG в временный каталог, подставной
# grub2-mkconfig. Everything in a sandbox: BS_GRUB_CONFIG/BS_GRUB_CFG point at a
# temp dir, grub2-mkconfig is fake.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
load "lib/system/bootloader"

SANDBOX=""
ORIG_PATH="${PATH}"
REAL_CHMOD="$(command -v chmod)"

eq() { testframework::assert_equal "$@"; }

check() {
    local -r name="${1}"
    shift
    if "$@"; then
        testframework::assert_true "true" "${name}"
    else
        testframework::assert_true "false" "${name}"
    fi
}

fake() {
    local -r name="${1}" rc="${2:-0}" out="${3:-}"
    rm -f "${SANDBOX}/bin/${name}"
    printf '#!/bin/bash\necho "%s $*" >> "%s/calls"\n[ -z %q ] || printf "%%s\\n" %q\nexit %s\n' \
        "${name}" "${SANDBOX}" "${out}" "${out}" "${rc}" > "${SANDBOX}/bin/${name}"
    "${REAL_CHMOD}" +x "${SANDBOX}/bin/${name}"
}

sandbox_new() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "${SANDBOX}/bin"
    : > "${SANDBOX}/calls"
    local tool real
    for tool in bash sh cat cp mv rm mkdir chmod grep sed head tail cut tr wc dirname basename mktemp date uname id ls readlink stat awk touch sort env tput ln sleep find; do
        real="$(PATH="${ORIG_PATH}" command -v "${tool}" 2>/dev/null)" || continue
        ln -sf "${real}" "${SANDBOX}/bin/${tool}"
    done
    export PATH="${SANDBOX}/bin"
}

sandbox_drop() {
    export PATH="${ORIG_PATH}"
    rm -rf "${SANDBOX:?}"
}

main() {
    print_header "Bootloader Unit Tests / Модульные тесты bootloader"
    testframework::init
    local rc bak

    testframework::section "detect / определение"
    sandbox_new
    printf 'GRUB_TIMEOUT=5\n' > "${SANDBOX}/grub"
    eq "grub" "$(BS_GRUB_CONFIG="${SANDBOX}/grub" system::bootloader::detect)" "grub config detected"
    sandbox_drop

    testframework::section "grub_set: валидация / validation"
    sandbox_new
    printf 'GRUB_TIMEOUT=5\nGRUB_DEFAULT=saved\n' > "${SANDBOX}/grub"
    rc=0; BS_GRUB_CONFIG="${SANDBOX}/grub" system::bootloader::grub_set "GRUB_TIMEOUT" "abc" >/dev/null 2>&1 || rc=$?
    check "non-integer timeout rejected" test "${rc}" -ne 0
    rc=0; BS_GRUB_CONFIG="${SANDBOX}/grub" system::bootloader::grub_set "bad key" "1" >/dev/null 2>&1 || rc=$?
    check "bad key rejected" test "${rc}" -ne 0
    rc=0; BS_GRUB_CONFIG="${SANDBOX}/grub" system::bootloader::grub_set "GRUB_DEFAULT" 'a"b' >/dev/null 2>&1 || rc=$?
    check "quote in value rejected" test "${rc}" -ne 0
    rc=0; BS_GRUB_CONFIG="${SANDBOX}/grub" system::bootloader::grub_set "GRUB_DEFAULT" $'a\nb' >/dev/null 2>&1 || rc=$?
    check "newline in value rejected" test "${rc}" -ne 0
    eq "GRUB_TIMEOUT=5" "$(head -1 "${SANDBOX}/grub")" "file untouched after rejections"
    sandbox_drop

    testframework::section "grub_set/get: запись и чтение / write and read"
    sandbox_new
    printf 'GRUB_TIMEOUT=5\nGRUB_DEFAULT=saved\nGRUB_CMDLINE_LINUX="rhgb quiet"\n' > "${SANDBOX}/grub"
    BS_GRUB_CONFIG="${SANDBOX}/grub" system::bootloader::grub_set "GRUB_TIMEOUT" "10" >/dev/null 2>&1
    eq 'GRUB_TIMEOUT="10"' "$(grep '^GRUB_TIMEOUT=' "${SANDBOX}/grub")" "timeout replaced and quoted"
    eq "GRUB_DEFAULT=saved" "$(grep '^GRUB_DEFAULT=' "${SANDBOX}/grub")" "other key kept"
    eq "rhgb quiet" "$(BS_GRUB_CONFIG="${SANDBOX}/grub" system::bootloader::grub_get GRUB_CMDLINE_LINUX)" "grub_get strips quotes"
    BS_GRUB_CONFIG="${SANDBOX}/grub" system::bootloader::grub_set "GRUB_DISABLE_RECOVERY" "true" >/dev/null 2>&1
    eq 'GRUB_DISABLE_RECOVERY="true"' "$(grep '^GRUB_DISABLE_RECOVERY=' "${SANDBOX}/grub")" "new key appended"
    sandbox_drop

    testframework::section "grub_backup/restore: бэкап и откат / backup and rollback"
    sandbox_new
    printf 'GRUB_TIMEOUT=5\n' > "${SANDBOX}/grub"
    bak="$(BS_GRUB_CONFIG="${SANDBOX}/grub" system::bootloader::grub_backup)"
    eq "GRUB_TIMEOUT=5" "$(head -1 "${bak}")" "backup content"
    printf 'GRUB_TIMEOUT=99\n' > "${SANDBOX}/grub"
    BS_GRUB_CONFIG="${SANDBOX}/grub" system::bootloader::grub_restore "${bak}" >/dev/null 2>&1
    eq "GRUB_TIMEOUT=5" "$(head -1 "${SANDBOX}/grub")" "restored"
    sandbox_drop

    testframework::section "regenerate: успех и сбой / success and failure"
    sandbox_new
    fake grub2-mkconfig 0
    BS_GRUB_CFG="${SANDBOX}/grub.cfg" system::bootloader::regenerate >/dev/null 2>&1
    check "grub2-mkconfig called" grep -qF 'grub2-mkconfig -o '"${SANDBOX}"'/grub.cfg' "${SANDBOX}/calls"
    sandbox_drop
    sandbox_new
    fake grub2-mkconfig 1
    rc=0; BS_GRUB_CFG="${SANDBOX}/grub.cfg" system::bootloader::regenerate >/dev/null 2>&1 || rc=$?
    check "grub2-mkconfig failure -> non-zero" test "${rc}" -ne 0
    sandbox_drop

    testframework::summary
}

main "$@"
