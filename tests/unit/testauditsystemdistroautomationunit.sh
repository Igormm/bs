#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testauditsystemdistroautomationunit.sh — scenario-audit regression tests for
# lib/automation, lib/system/{distrologic,display,devices}
# tests/unit/testauditsystemdistroautomationunit.sh — регрессионные тесты сценарного аудита
# lib/automation, lib/system/{distrologic,display,devices}
#
# Всё в песочнице: подставные apt/dnf/systemctl/xrandr/mkfs, настоящих админ-команд в PATH нет.
# Everything runs in a sandbox: fake apt/dnf/systemctl/xrandr/mkfs, no real admin tools in PATH.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

load "lib/automation"
load "lib/system/distrologic"
load "lib/system/display"
load "lib/system/devices"
load "lib/system/platformcheck"

# quiet CMD... — команда без вывода, код возврата сохраняется / silent command, status kept
quiet() { "$@" >/dev/null 2>&1; }

main() {
    print_header "Automation/distrologic/display audit tests / Тесты аудита automation, distrologic, display"
    testframework::init
    local rc out

    testframework::section "detect_package_manager: stdout — только имя / stdout is the bare name"
    sandbox_new
    fake apt 0
    out="$(automation::system::detect_package_manager 2>/dev/null)"
    eq "apt" "${out}" "stdout holds only 'apt' (log goes to stderr)"
    sandbox_drop

    testframework::section "manage_packages: действительно вызывает менеджер / really calls the manager"
    sandbox_new
    fake apt 0
    automation::system::manage_packages install foo bar >/dev/null 2>&1
    eq "apt install -y foo bar" "$(cat "${SANDBOX}/calls")" "apt install -y foo bar"
    : > "${SANDBOX}/calls"
    fake apt 100
    rc=0; automation::system::manage_packages install foo >/dev/null 2>&1 || rc=$?
    check "apt failure -> non-zero" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "update_package_cache: dnf check-update=100 — успех / 100 is success"
    sandbox_new
    fake dnf 100
    rc=0; automation::system::update_package_cache >/dev/null 2>&1 || rc=$?
    eq "0" "${rc}" "exit 100 (updates available) is success"
    fake dnf 1
    rc=0; automation::system::update_package_cache >/dev/null 2>&1 || rc=$?
    check "real dnf failure -> non-zero" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "control_service: сбой systemctl / systemctl failure"
    sandbox_new
    fake systemctl 5
    rc=0; automation::system::control_service nginx restart >/dev/null 2>&1 || rc=$?
    check "failure not reported as success" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "check_sudo_access: форматы sudo -l / sudo -l formats"
    sandbox_new
    for line in "(ALL : ALL) ALL" "(ALL) ALL" "(root) NOPASSWD: ALL"; do
        printf '#!/bin/bash\necho "User x may run the following commands:"\necho "    %s"\n' "${line}" > "${SANDBOX}/bin/sudo"
        "${REAL_CHMOD}" +x "${SANDBOX}/bin/sudo"
        check "'${line}' means sudo access" quiet automation::security::check_sudo_access x
    done
    printf '#!/bin/bash\necho "User x is not allowed to run sudo"\nexit 1\n' > "${SANDBOX}/bin/sudo"
    "${REAL_CHMOD}" +x "${SANDBOX}/bin/sudo"
    rc=0; automation::security::check_sudo_access x >/dev/null 2>&1 || rc=$?
    check "no rules -> FAIL" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "configure_log_rotation: чужой конфиг не затирается / foreign config kept"
    sandbox_new
    mkdir -p "${SANDBOX}/logrotate.d"
    printf 'distro rules\n' > "${SANDBOX}/logrotate.d/dpkg.log"
    printf 'distro rules\n' > "${SANDBOX}/logrotate.d/bs-dpkg.log"
    rc=0; BS_LOGROTATE_DIR="${SANDBOX}/logrotate.d" automation::security::configure_log_rotation /var/log/dpkg.log >/dev/null 2>&1 || rc=$?
    check "foreign bs-<name> file is not overwritten" test "${rc}" -ne 0
    eq "distro rules" "$(cat "${SANDBOX}/logrotate.d/bs-dpkg.log")" "foreign content intact"
    BS_LOGROTATE_DIR="${SANDBOX}/logrotate.d" automation::security::configure_log_rotation /var/log/myapp.log >/dev/null 2>&1
    check "own config written" grep -q '^/var/log/myapp.log {' "${SANDBOX}/logrotate.d/bs-myapp.log"
    BS_LOGROTATE_DIR="${SANDBOX}/logrotate.d" automation::security::configure_log_rotation /var/log/myapp.log >/dev/null 2>&1
    eq "1" "$(grep -c '^/var/log/myapp.log {' "${SANDBOX}/logrotate.d/bs-myapp.log")" "rerun rewrites, does not duplicate"
    eq "distro rules" "$(cat "${SANDBOX}/logrotate.d/dpkg.log")" "distribution's own rule untouched"
    sandbox_drop

    testframework::section "manage_route: flush и мусор отвергаются / flush and junk rejected"
    sandbox_new
    fake ip 0
    rc=0; automation::network::manage_route flush 10.0.0.0/8 1.1.1.1 >/dev/null 2>&1 || rc=$?
    check "flush rejected" test "${rc}" -ne 0
    eq "" "$(cat "${SANDBOX}/calls")" "ip never called"
    fake ip 2
    rc=0; automation::network::manage_route add 10.0.0.0/8 1.1.1.1 >/dev/null 2>&1 || rc=$?
    check "ip failure -> non-zero" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "pkg_update_all (redhat): check-update=100 не блокирует upgrade / does not block upgrade"
    sandbox_new
    fake dnf 100
    DISTRO_FAMILY="redhat" system::distrologic::pkg_update_all >/dev/null 2>&1 || true
    check "dnf upgrade -y was called" grep -qx 'dnf upgrade -y' "${SANDBOX}/calls"
    sandbox_drop

    testframework::section "openrc: код возврата настоящей команды / real exit status"
    sandbox_new
    fake rc-service 3
    fake rc-update 0
    rc=0; system::distrologic::service_manage_openrc sshd start >/dev/null 2>&1 || rc=$?
    check "rc-service failure -> non-zero" test "${rc}" -ne 0
    system::distrologic::service_manage_openrc sshd enable >/dev/null 2>&1
    check "enable = rc-update add" grep -qx 'rc-update add sshd default' "${SANDBOX}/calls"
    sandbox_drop

    testframework::section "apparmor: имя профиля — не путь / profile is not a path"
    sandbox_new
    fake apparmor_parser 0
    fake aa-complain 0
    fake rm 0    # подставной rm: настоящий /etc/... тронуть нельзя / fake rm: real /etc/... must stay untouched
    rc=0; system::distrologic::security_configure_apparmor disable "../../passwd" >/dev/null 2>&1 || rc=$?
    check "traversal profile rejected" test "${rc}" -ne 0
    eq "0" "$(grep -c '^rm .*force-enabled' "${SANDBOX}/calls")" "rm never called on force-enabled/"
    rc=0; system::distrologic::security_configure_apparmor complain >/dev/null 2>&1 || rc=$?
    check "complain without profile -> error" test "${rc}" -ne 0
    ln -sf "$(PATH="${ORIG_PATH}" command -v rm)" "${SANDBOX}/bin/rm"
    sandbox_drop

    testframework::section "fs_format: смонтированное, пустое, dry-run / mounted, empty, dry-run"
    sandbox_new
    fake mkfs.ext4 0
    fake mkfs.xfs 0
    printf '/dev/sdb1 /mnt ext4 rw 0 0\n' > "${SANDBOX}/mounts"
    rc=0; BS_PROC_MOUNTS="${SANDBOX}/mounts" system::distrologic::fs_format_ext4 /dev/sdb1 >/dev/null 2>&1 || rc=$?
    check "mounted device refused" test "${rc}" -ne 0
    rc=0; BS_PROC_MOUNTS="${SANDBOX}/mounts" system::distrologic::fs_format_xfs "" >/dev/null 2>&1 || rc=$?
    check "empty device refused" test "${rc}" -ne 0
    rc=0; BS_PROC_MOUNTS="${SANDBOX}/mounts" FRAMEWORK_DRY_RUN=true system::distrologic::fs_format_ext4 /dev/sdc1 >/dev/null 2>&1 || rc=$?
    eq "0" "${rc}" "dry-run reports success"
    eq "" "$(cat "${SANDBOX}/calls")" "mkfs never called (mounted / empty / dry-run)"
    BS_PROC_MOUNTS="${SANDBOX}/mounts" system::distrologic::fs_format_ext4 /dev/sdc1 >/dev/null 2>&1
    check "normal run calls mkfs.ext4" grep -qx 'mkfs.ext4 /dev/sdc1' "${SANDBOX}/calls"
    sandbox_drop

    testframework::section "display::manager: сначала проверка, потом остановка / validate before stop"
    sandbox_new
    fake systemctl 0
    rc=0; system::display::manager "nonsense" >/dev/null 2>&1 || rc=$?
    check "unknown manager refused" test "${rc}" -ne 0
    rc=0; system::display::manager "gdm" >/dev/null 2>&1 || rc=$?
    check "not installed manager refused" test "${rc}" -ne 0
    eq "" "$(cat "${SANDBOX}/calls")" "display-manager NOT stopped on refusal"
    fake gdm 0
    system::display::manager "gdm" >/dev/null 2>&1
    check "installed: stop, enable -f, set-default" bash -c "grep -qx 'systemctl stop display-manager' '${SANDBOX}/calls' && grep -qx 'systemctl enable -f gdm' '${SANDBOX}/calls' && grep -qx 'systemctl set-default graphical.target' '${SANDBOX}/calls'"
    sandbox_drop

    testframework::section "display::multi primary: несуществующий вывод не гасит всё / bogus output keeps screens"
    sandbox_new
    printf '#!/bin/bash\necho "xrandr $*" >> "%s/calls"\nif [ "$1" = --query ]; then\n  echo "eDP-1 connected primary 1920x1080+0+0"\n  echo "HDMI-1 connected 1920x1080+1920+0"\n  echo "DP-1 disconnected"\nfi\nexit 0\n' "${SANDBOX}" > "${SANDBOX}/bin/xrandr"
    "${REAL_CHMOD}" +x "${SANDBOX}/bin/xrandr"
    rc=0; system::display::multi primary DP-9 >/dev/null 2>&1 || rc=$?
    check "unknown primary refused" test "${rc}" -ne 0
    eq "0" "$(grep -c -- '--off' "${SANDBOX}/calls")" "no output switched off"
    system::display::multi primary HDMI-1 >/dev/null 2>&1
    check "only the other output is switched off" bash -c "grep -qx 'xrandr --output eDP-1 --off' '${SANDBOX}/calls' && ! grep -q 'HDMI-1 --off' '${SANDBOX}/calls'"
    sandbox_drop

    testframework::section "display::resolution: сбой xrandr / xrandr failure"
    sandbox_new
    fake xrandr 1
    rc=0; system::display::resolution 800x600 HDMI-1 >/dev/null 2>&1 || rc=$?
    check "failure not reported as success" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "devices::display brightness: проверка значения / value check"
    sandbox_new
    fake xrandr 0
    for v in 0 101 abc 'a[$(touch /tmp/never)]'; do
        rc=0; system::devices::display brightness "${v}" >/dev/null 2>&1 || rc=$?
        check "brightness '${v}' rejected" test "${rc}" -ne 0
    done
    eq "" "$(cat "${SANDBOX}/calls")" "xrandr never called for a bad value"
    sandbox_drop

    testframework::section "platformcheck::show_report: отчёт не ставит пакеты / a report installs nothing"
    sandbox_new
    rm -f "${SANDBOX}/bin/awk"
    fake apt-get 0
    fake dnf 0
    fake yum 0
    platformcheck::show_report >/dev/null 2>&1 || true
    eq "" "$(cat "${SANDBOX}/calls")" "no package manager was run by the report"
    sandbox_drop

    testframework::summary
}

main "$@"
