#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testauditsystemsecurityunit.sh — scenario-audit regression tests for lib/system/security
# tests/unit/testauditsystemsecurityunit.sh — регрессионные тесты сценарного аудита lib/system/security
#
# Всё в песочнице: подставные команды в PATH, пути конфигов через переменные окружения.
# Everything runs in a sandbox: fake commands in PATH, config paths via environment variables.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
load "lib/system/security"

SANDBOX=""
ORIG_PATH="${PATH}"
REAL_CHMOD="$(command -v chmod)"

# check NAME CMD... — зелёный, если команда успешна / green when the command succeeds
check() {
    local -r name="${1}"
    shift
    if "$@"; then
        testframework::assert_true "true" "${name}"
    else
        testframework::assert_true "false" "${name}"
    fi
}

# fake NAME [EXIT] — подставная команда, пишет вызов в $SANDBOX/calls
# fake NAME [EXIT] — fake command, records the call in $SANDBOX/calls
fake() {
    local -r name="${1}" rc="${2:-0}"
    rm -f "${SANDBOX}/bin/${name}"    # never write through a symlink to a real tool / не писать через симлинк в настоящую утилиту
    printf '#!/bin/bash\necho "%s $*" >> "%s/calls"\nexit %s\n' "${name}" "${SANDBOX}" "${rc}" > "${SANDBOX}/bin/${name}"
    "${REAL_CHMOD}" +x "${SANDBOX}/bin/${name}"
}

eq() { testframework::assert_equal "$@"; }

sandbox_new() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "${SANDBOX}/bin" "${SANDBOX}/etc"
    : > "${SANDBOX}/calls"
    # PATH: только подставные команды и белый список базовых утилит (симлинки). Настоящих
    # ufw/systemctl/iptables/passwd в PATH нет — тест не может тронуть систему.
    # PATH: fakes plus a whitelist of base tools (symlinks) only. No real
    # ufw/systemctl/iptables/passwd in PATH — the test cannot touch the system.
    local tool real
    for tool in bash sh cat cp mv rm mkdir chmod grep sed head tail cut tr wc dirname basename mktemp date uname id ls readlink stat awk touch sort env tput; do
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
    print_header "Security audit tests / Тесты аудита security"
    testframework::init

    testframework::section "firewall: сбой ufw не выдаётся за успех / ufw failure is not success"
    sandbox_new
    fake ufw 1
    local rc=0
    system::security::firewall enable >/dev/null 2>&1 || rc=$?
    check "ufw enable failure -> non-zero" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "firewall status: вывод не теряется / status output is not swallowed"
    sandbox_new
    printf '#!/bin/bash\necho "Status: active"\n' > "${SANDBOX}/bin/ufw"
    chmod +x "${SANDBOX}/bin/ufw"
    local out
    out="$(system::security::firewall status 2>&1)"
    check "ufw status prints its output" grep -q 'Status: active' <<< "${out}"
    sandbox_drop

    testframework::section "firewall disable (iptables): политики ACCEPT до сброса / policies before flush"
    sandbox_new
    fake iptables 0
    system::security::firewall disable >/dev/null 2>&1
    local first
    first="$(head -1 "${SANDBOX}/calls")"
    eq "iptables -P INPUT ACCEPT" "${first}" "INPUT policy reset before the flush"
    eq "1" "$(grep -c -- 'iptables -F' "${SANDBOX}/calls")" "flush happens once"
    sandbox_drop

    testframework::section "ssh: порт проверяется / port is validated"
    sandbox_new
    fake ufw 0
    rc=0
    system::security::ssh "22; reboot" >/dev/null 2>&1 || rc=$?
    check "non-numeric port rejected" test "${rc}" -ne 0
    eq "" "$(cat "${SANDBOX}/calls")" "no command ran for an invalid port"
    sandbox_drop

    testframework::section "password_policy: строка pam_unix сохраняется / pam_unix line survives"
    sandbox_new
    mkdir -p "${SANDBOX}/pam"
    printf 'auth required pam_env.so\npassword    sufficient    pam_unix.so sha512 shadow\npassword required pam_deny.so\n' > "${SANDBOX}/pam/system-auth"
    BS_PAM_DIR="${SANDBOX}/pam" BS_LOGIN_DEFS="${SANDBOX}/nologindefs" system::security::password_policy >/dev/null 2>&1
    eq "1" "$(grep -c 'pam_unix.so' "${SANDBOX}/pam/system-auth")" "pam_unix line kept"
    eq "1" "$(grep -c 'pam_pwquality.so' "${SANDBOX}/pam/system-auth")" "pwquality line added"
    local ln_unix ln_pwq
    ln_unix="$(grep -n 'pam_unix.so' "${SANDBOX}/pam/system-auth" | cut -d: -f1)"
    ln_pwq="$(grep -n 'pam_pwquality.so' "${SANDBOX}/pam/system-auth" | cut -d: -f1)"
    check "pwquality goes before pam_unix" test "${ln_pwq}" -lt "${ln_unix}"
    sandbox_drop

    testframework::section "disable_root: нет другого администратора -> отказ / no other admin -> refuse"
    sandbox_new
    printf '#!/bin/bash\n[ "$2" = sudo ] && echo "sudo:x:27:"\nexit 0\n' > "${SANDBOX}/bin/getent"
    chmod +x "${SANDBOX}/bin/getent"
    fake passwd 0
    printf 'PermitRootLogin yes\n' > "${SANDBOX}/sshd_config"
    rc=0
    BS_SSHD_MAIN="${SANDBOX}/sshd_config" system::security::disable_root >/dev/null 2>&1 || rc=$?
    check "refused without a sudo user" test "${rc}" -ne 0
    eq "PermitRootLogin yes" "$(cat "${SANDBOX}/sshd_config")" "sshd_config untouched"
    eq "" "$(cat "${SANDBOX}/calls")" "root password not locked"
    sandbox_drop

    testframework::section "disable_root: sshd -t отвергает конфиг -> откат / sshd -t rejects -> rollback"
    sandbox_new
    printf '#!/bin/bash\n[ "$2" = sudo ] && echo "sudo:x:27:alice"\nexit 0\n' > "${SANDBOX}/bin/getent"
    chmod +x "${SANDBOX}/bin/getent"
    fake passwd 0
    fake sshd 255
    fake systemctl 0
    printf '# PermitRootLogin yes\nPort 22\n' > "${SANDBOX}/sshd_config"
    rc=0
    BS_SSHD_MAIN="${SANDBOX}/sshd_config" system::security::disable_root >/dev/null 2>&1 || rc=$?
    check "invalid config -> failure" test "${rc}" -ne 0
    eq "# PermitRootLogin yes
Port 22" "$(cat "${SANDBOX}/sshd_config")" "sshd_config restored"
    eq "0" "$(grep -c '^passwd' "${SANDBOX}/calls")" "root password not locked after rollback"
    sandbox_drop

    testframework::section "disable_root: успешный путь / happy path"
    sandbox_new
    printf '#!/bin/bash\n[ "$2" = sudo ] && echo "sudo:x:27:alice"\nexit 0\n' > "${SANDBOX}/bin/getent"
    chmod +x "${SANDBOX}/bin/getent"
    fake passwd 0
    fake sshd 0
    fake systemctl 0
    printf '#PermitRootLogin yes\nPort 22\n' > "${SANDBOX}/sshd_config"
    BS_SSHD_MAIN="${SANDBOX}/sshd_config" system::security::disable_root >/dev/null 2>&1
    eq "PermitRootLogin no" "$(head -1 "${SANDBOX}/sshd_config")" "PermitRootLogin no on top"
    eq "1" "$(grep -c 'passwd -l root' "${SANDBOX}/calls")" "root locked"
    sandbox_drop

    testframework::summary
}

main "$@"
