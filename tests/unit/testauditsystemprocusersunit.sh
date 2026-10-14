#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testauditsystemprocusersunit.sh — scenario-audit regression tests for
# lib/system/{processes,users,permissions,utils}
# tests/unit/testauditsystemprocusersunit.sh — регрессионные тесты сценарного аудита
# lib/system/{processes,users,permissions,utils}
#
# Всё в песочнице: подставные chpasswd/chmod/pkill/userdel, настоящие только pgrep/ps (чтение)
# и свои же процессы sleep. Everything runs in a sandbox: fake chpasswd/chmod/pkill/userdel;
# only pgrep/ps (read-only) and our own sleep processes are real.

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

load "lib/system/utils"
load "lib/system/processes"
load "lib/system/users"
load "lib/system/permissions"

main() {
    print_header "Process/users/permissions audit tests / Тесты аудита процессов, пользователей, прав"
    testframework::init
    local rc out

    testframework::section "generate_password: pipefail / pipefail"
    sandbox_new
    out="$(set -o pipefail; system::utils::security_generate_password 24; echo "rc=$?")"
    check "returns 0 under pipefail" grep -qx 'rc=0' <<< "${out}"
    eq "24" "$(printf '%s' "${out%$'\n'rc=*}" | wc -c | tr -d ' ')" "requested length"
    rc=0; system::utils::security_generate_password abc >/dev/null 2>&1 || rc=$?
    check "non-numeric length rejected" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "process_kill_by_name: пустой шаблон / empty pattern"
    sandbox_new
    fake pkill 0
    rc=0; system::utils::process_kill_by_name "" >/dev/null 2>&1 || rc=$?
    check "empty pattern rejected" test "${rc}" -ne 0
    rc=0; system::utils::process_kill_by_name "   " >/dev/null 2>&1 || rc=$?
    check "blank pattern rejected" test "${rc}" -ne 0
    eq "" "$(cat "${SANDBOX}/calls")" "pkill never called"
    sandbox_drop

    testframework::section "process_stop: опасные PID / dangerous PIDs"
    sandbox_new
    # kill как функция-заглушка: ничего не посылаем, только записываем / kill is a stub
    # function: nothing is sent, the call is only recorded
    kill() { printf 'kill %s\n' "$*" >> "${SANDBOX}/calls"; }
    for pid in "" 0 1 -1 abc "1 2"; do
        rc=0; system::utils::process_stop "${pid}" >/dev/null 2>&1 || rc=$?
        check "PID '${pid}' rejected" test "${rc}" -ne 0
    done
    eq "" "$(cat "${SANDBOX}/calls")" "kill never called with a dangerous PID"
    unset -f kill
    sandbox_drop

    testframework::section "user_delete: root и пустое имя / root and empty name"
    sandbox_new
    fake userdel 0
    rc=0; system::utils::user_delete "" >/dev/null 2>&1 || rc=$?
    check "empty name rejected" test "${rc}" -ne 0
    rc=0; system::utils::user_delete "root" >/dev/null 2>&1 || rc=$?
    check "root rejected" test "${rc}" -ne 0
    rc=0; system::utils::user_delete "-f" >/dev/null 2>&1 || rc=$?
    check "option-like name rejected" test "${rc}" -ne 0
    eq "" "$(cat "${SANDBOX}/calls")" "userdel never called"
    sandbox_drop

    testframework::section "network_download: сбой не оставляет мусор и не трогает цель / failure keeps target"
    sandbox_new
    printf '#!/bin/bash\n# fake curl: writes an error page, fails like curl -f\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done\necho "<html>404</html>" > "$out"\nexit 22\n' > "${SANDBOX}/bin/curl"
    chmod +x "${SANDBOX}/bin/curl"
    printf 'old content\n' > "${SANDBOX}/target.txt"
    rc=0; system::utils::network_download "http://example.invalid/x" "${SANDBOX}/target.txt" >/dev/null 2>&1 || rc=$?
    check "failed download -> non-zero" test "${rc}" -ne 0
    eq "old content" "$(cat "${SANDBOX}/target.txt")" "existing target intact"
    eq "0" "$(find "${SANDBOX}" -maxdepth 1 -name '*part*' | wc -l | tr -d ' ')" "no .part leftovers"
    sandbox_drop

    testframework::section "set_password: перевод строки в пароле / newline in password"
    sandbox_new
    printf '#!/bin/bash\ncat >> "%s/chpasswd.in"\nexit 0\n' "${SANDBOX}" > "${SANDBOX}/bin/chpasswd"
    chmod +x "${SANDBOX}/bin/chpasswd"
    rc=0; system::users::set_password "$(id -un)" $'hunter2\nroot:owned' >/dev/null 2>&1 || rc=$?
    check "newline password rejected" test "${rc}" -ne 0
    check "chpasswd got no input" test ! -s "${SANDBOX}/chpasswd.in"
    system::users::set_password "$(id -un)" "plain pass" >/dev/null 2>&1
    eq "$(id -un):plain pass" "$(cat "${SANDBOX}/chpasswd.in")" "normal password passes as one line"
    sandbox_drop

    testframework::section "set_password: passwd --stdin получает голый пароль / bare password"
    sandbox_new
    printf '#!/bin/bash\ncat >> "%s/passwd.in"\nexit 0\n' "${SANDBOX}" > "${SANDBOX}/bin/passwd"
    chmod +x "${SANDBOX}/bin/passwd"
    system::users::set_password "$(id -un)" "s3cret" >/dev/null 2>&1
    eq "s3cret" "$(cat "${SANDBOX}/passwd.in")" "password without the user: prefix"
    sandbox_drop

    testframework::section "permissions::recursive: системные корни / system roots"
    sandbox_new
    fake chmod 0
    for dir in / /etc /etc/ /usr "/tmp/../etc"; do
        rc=0; system::permissions::recursive "${dir}" 777 >/dev/null 2>&1 || rc=$?
        check "recursive chmod on '${dir}' refused" test "${rc}" -ne 0
    done
    eq "" "$(cat "${SANDBOX}/calls")" "chmod never called on system roots"
    mkdir -p "${SANDBOX}/proj"
    system::permissions::recursive "${SANDBOX}/proj" 755 >/dev/null 2>&1
    check "ordinary directory still works" grep -qF "chmod -R 755 ${SANDBOX}/proj" "${SANDBOX}/calls"
    sandbox_drop

    testframework::section "processes: настоящие процессы-жертвы / real victim processes"
    local real_sleep victim_dir
    real_sleep="$(command -v sleep)"
    sandbox_new
    ln -sf "$(PATH="${ORIG_PATH}" command -v pgrep)" "${SANDBOX}/bin/pgrep"
    ln -sf "$(PATH="${ORIG_PATH}" command -v ps)" "${SANDBOX}/bin/ps"
    victim_dir="${SANDBOX}/v"
    mkdir -p "${victim_dir}"
    cp "${real_sleep}" "${victim_dir}/longnamedprocess_x"
    "${victim_dir}/longnamedprocess_x" 60 &
    local v1=$!
    "${victim_dir}/longnamedprocess_x" 61 &
    local v2=$!
    sleep 0.3
    check "is_running matches a name longer than 15 chars" system::processes::is_running longnamedprocess_x
    out="$(system::processes::find longnamedprocess_x 2>&1 || true)"
    eq "3" "$(printf '%s\n' "${out}" | grep -c .)" "find lists header + both processes"
    kill "${v1}" "${v2}" 2>/dev/null || true
    wait "${v1}" "${v2}" 2>/dev/null || true
    sandbox_drop

    testframework::section "kill_by_name: не убивает вызывающего / does not kill the caller"
    sandbox_new
    ln -sf "$(PATH="${ORIG_PATH}" command -v pgrep)" "${SANDBOX}/bin/pgrep"
    ln -sf "$(PATH="${ORIG_PATH}" command -v ps)" "${SANDBOX}/bin/ps"
    # Дочерняя оболочка с шаблоном в собственной командной строке / child shell whose
    # own command line contains the pattern
    out="$(PATH="${SANDBOX}/bin" BS_SILENT=1 ${TEST_BASH} -c '
        source "$1/bootstrap/init.sh" >/dev/null 2>&1
        load "lib/system/processes" >/dev/null 2>&1
        system::processes::kill_by_name "$2" >/dev/null 2>&1
        echo survived
    ' bash "${BS_PROJECT_ROOT}" "AUDIT_TOKEN_QX7" 2>&1 || true)"
    check "caller survives kill_by_name of its own command line" grep -q survived <<< "${out}"
    sandbox_drop

    testframework::summary
}

main "$@"
