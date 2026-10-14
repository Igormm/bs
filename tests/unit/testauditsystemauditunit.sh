#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testauditsystemauditunit.sh — scenario-audit regression tests for lib/audit/systemaudit
# tests/unit/testauditsystemauditunit.sh — регрессионные тесты сценарного аудита lib/audit/systemaudit
#
# Всё в песочнице: HOME во временном каталоге, подставные find/iptables/ufw, пути конфигов
# через BS_SSHD_MAIN / BS_LOGIN_DEFS. Everything runs in a sandbox: HOME in a temp dir,
# fake find/iptables/ufw, config paths via BS_SSHD_MAIN / BS_LOGIN_DEFS.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

SANDBOX=""
ORIG_PATH="${PATH}"
REAL_CHMOD="$(command -v chmod)"

eq() { testframework::assert_equal "$@"; }

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

# fake NAME [EXIT] [STDOUT] — подставная команда, пишет вызов в $SANDBOX/calls
# fake NAME [EXIT] [STDOUT] — fake command, records the call in $SANDBOX/calls
fake() {
    local -r name="${1}" rc="${2:-0}" out="${3:-}"
    rm -f "${SANDBOX}/bin/${name}"    # never write through a symlink to a real tool / не писать через симлинк в настоящую утилиту
    printf '#!/bin/bash\necho "%s $*" >> "%s/calls"\n[ -z %q ] || printf "%%s\\n" %q\nexit %s\n' \
        "${name}" "${SANDBOX}" "${out}" "${out}" "${rc}" > "${SANDBOX}/bin/${name}"
    "${REAL_CHMOD}" +x "${SANDBOX}/bin/${name}"
}

# PATH: только подставные команды и белый список базовых утилит (симлинки). Настоящих
# systemctl/ufw/useradd/localectl в PATH нет — тест не может тронуть систему.
# PATH: fakes plus a whitelist of base tools (symlinks) only. No real
# systemctl/ufw/useradd/localectl in PATH — the test cannot touch the system.
sandbox_new() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "${SANDBOX}/bin"
    : > "${SANDBOX}/calls"
    local tool real
    for tool in bash sh cat cp mv rm mkdir chmod grep sed head tail cut tr wc dirname basename mktemp date uname id ls readlink stat awk touch sort env tput ln sleep; do
        real="$(PATH="${ORIG_PATH}" command -v "${tool}" 2>/dev/null)" || continue
        ln -sf "${real}" "${SANDBOX}/bin/${tool}"
    done
    export PATH="${SANDBOX}/bin"
}

sandbox_drop() {
    export PATH="${ORIG_PATH}"
    rm -rf "${SANDBOX:?}"
}

# Пути отчётов вычисляются из HOME при загрузке модуля / report paths come from HOME at load
HOME="$(mktemp -d)"
export HOME
load "lib/audit/systemaudit"

main() {
    print_header "System audit lib tests / Тесты библиотеки аудита системы"
    testframework::init
    local rc out

    testframework::section "run <категория>: оценка считается / single-category audit is scored"
    sandbox_new
    # Подменяем проверку: одна критическая находка / replace the check: one critical finding
    systemaudit::compliance::run() {
        AUDIT_FINDINGS+=("$(systemaudit::create_finding "t" "d" "${AUDIT_SEVERITY_CRITICAL}" "compliance" "r")")
    }
    systemaudit::run compliance json >/dev/null 2>&1
    local report
    report="$(ls "${AUDIT_REPORT_DIR}"/audit_*.json | head -1)"
    check "report was written" test -s "${report}"
    check "score reflects the critical finding (75), not 100" grep -q '"score": 75' "${report}"
    sandbox_drop

    testframework::section "generate_report: нельзя записать -> ошибка / unwritable -> error"
    sandbox_new
    local saved_dir="${AUDIT_REPORT_DIR}"
    # каталог отчётов подменяется обычным файлом / the report dir path is occupied by a file
    # (AUDIT_REPORT_DIR объявлен readonly — проверяем через подкаталог-файл ниже по пути)
    printf 'x' > "${SANDBOX}/blocker"
    systemaudit::generate_text_report() { return 1; }
    rc=0; systemaudit::generate_report text >/dev/null 2>&1 || rc=$?
    check "failed write is not reported as success" test "${rc}" -ne 0
    unset -f systemaudit::generate_text_report
    : "${saved_dir}"
    sandbox_drop

    testframework::section "ssh: нет строки Protocol — не находка / absent Protocol is not a finding"
    sandbox_new
    printf 'Port 22\nPermitRootLogin   yes\n' > "${SANDBOX}/sshd_config"
    AUDIT_FINDINGS=()
    BS_SSHD_MAIN="${SANDBOX}/sshd_config" systemaudit::security::check_ssh_config
    eq "0" "${#AUDIT_FINDINGS[@]}" "modern sshd_config without Protocol: no finding"
    printf 'Protocol 2,1\n' > "${SANDBOX}/sshd_config"
    AUDIT_FINDINGS=()
    BS_SSHD_MAIN="${SANDBOX}/sshd_config" systemaudit::security::check_ssh_config
    eq "1" "${#AUDIT_FINDINGS[@]}" "explicit Protocol 2,1 is a finding"
    printf 'Port 22\nPermitRootLogin   yes\n' > "${SANDBOX}/sshd_config"
    AUDIT_FINDINGS=()
    BS_SSHD_MAIN="${SANDBOX}/sshd_config" systemaudit::security::check_root_login
    eq "1" "${#AUDIT_FINDINGS[@]}" "PermitRootLogin with extra spaces is found"
    sandbox_drop

    testframework::section "password_policy: нет PASS_MAX_DAYS / absent PASS_MAX_DAYS"
    sandbox_new
    printf 'UID_MIN 1000\n' > "${SANDBOX}/login.defs"
    AUDIT_FINDINGS=()
    BS_LOGIN_DEFS="${SANDBOX}/login.defs" systemaudit::security::check_password_policy
    eq "1" "${#AUDIT_FINDINGS[@]}" "no PASS_MAX_DAYS means 'never expires' -> finding"
    printf 'PASS_MAX_DAYS   90\n' > "${SANDBOX}/login.defs"
    AUDIT_FINDINGS=()
    BS_LOGIN_DEFS="${SANDBOX}/login.defs" systemaudit::security::check_password_policy
    eq "0" "${#AUDIT_FINDINGS[@]}" "PASS_MAX_DAYS 90 is fine"
    sandbox_drop

    testframework::section "suid: считаются все файлы / all files counted"
    sandbox_new
    rm -f "${SANDBOX}/bin/find"
    printf '#!/bin/bash\nseq 1 50 | sed "s|^|/usr/bin/suid|"\n' > "${SANDBOX}/bin/find"
    "${REAL_CHMOD}" +x "${SANDBOX}/bin/find"
    ln -sf "$(PATH="${ORIG_PATH}" command -v seq)" "${SANDBOX}/bin/seq"
    AUDIT_FINDINGS=()
    systemaudit::security::check_suid_files
    check "title carries the real count (50), not the cap (20)" grep -q 'found: 50' <<< "${AUDIT_FINDINGS[*]}"
    sandbox_drop

    testframework::section "world-writable dirs: sticky-каталоги исключены / sticky dirs excluded"
    sandbox_new
    rm -f "${SANDBOX}/bin/find"
    printf '#!/bin/bash\necho "find $*" >> "%s/calls"\n' "${SANDBOX}" > "${SANDBOX}/bin/find"
    "${REAL_CHMOD}" +x "${SANDBOX}/bin/find"
    systemaudit::security::check_world_writable_dirs
    check "find skips sticky directories (! -perm -1000)" grep -qF -- '! -perm -1000' "${SANDBOX}/calls"
    sandbox_drop

    testframework::section "firewall: пустая цепочка — не межсетевой экран / empty chains are not a firewall"
    sandbox_new
    printf '#!/bin/bash\ncase "$1" in\n  -L) echo "Chain INPUT (policy ACCEPT)"; echo "target prot opt source destination";;\n  -S) echo "-P INPUT ACCEPT"; echo "-P FORWARD ACCEPT"; echo "-P OUTPUT ACCEPT";;\nesac\n' > "${SANDBOX}/bin/iptables"
    "${REAL_CHMOD}" +x "${SANDBOX}/bin/iptables"
    AUDIT_FINDINGS=()
    systemaudit::security::check_firewall_status
    eq "1" "${#AUDIT_FINDINGS[@]}" "default-accept iptables without rules -> 'No firewall'"
    printf '#!/bin/bash\ncase "$1" in\n  -S) echo "-P INPUT DROP"; echo "-A INPUT -p tcp --dport 22 -j ACCEPT";;\nesac\n' > "${SANDBOX}/bin/iptables"
    AUDIT_FINDINGS=()
    systemaudit::security::check_firewall_status
    eq "0" "${#AUDIT_FINDINGS[@]}" "iptables with rules -> firewall detected"
    sandbox_drop

    testframework::section "processes: имя команды, а не подстрока nc / command name, not substring"
    sandbox_new
    printf '#!/bin/bash\necho "irqbalance /usr/sbin/irqbalance"\necho "dbus-broker-launch /usr/bin/dbus-broker-launch --scope system"\necho "kworker/R-sync_wq [kworker/R-sync_wq]"\n' > "${SANDBOX}/bin/ps"
    "${REAL_CHMOD}" +x "${SANDBOX}/bin/ps"
    AUDIT_FINDINGS=()
    systemaudit::security::check_processes
    eq "0" "${#AUDIT_FINDINGS[@]}" "ordinary daemons are not suspicious"
    printf '#!/bin/bash\necho "nc nc -l -p 4444"\n' > "${SANDBOX}/bin/ps"
    AUDIT_FINDINGS=()
    systemaudit::security::check_processes
    eq "1" "${#AUDIT_FINDINGS[@]}" "a listening nc is suspicious"
    sandbox_drop

    testframework::summary
}

main "$@"
