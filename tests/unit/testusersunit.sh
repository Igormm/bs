#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testusersunit.sh — unit tests for lib/system/users (modify, group_info)
# tests/unit/testusersunit.sh — модульные тесты lib/system/users (modify, group_info)
#
# Всё в песочнице: подставные usermod/getent/id, запись вызовов в $SANDBOX/calls.
# Everything runs in a sandbox: fake usermod/getent/id, calls recorded in $SANDBOX/calls.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
load "lib/system/users"

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
    print_header "Users Unit Tests / Модульные тесты users"
    testframework::init
    local rc out

    testframework::section "modify: валидация / validation"
    sandbox_new
    fake usermod 0
    fake id 1
    rc=0; system::users::modify "" shell /bin/bash >/dev/null 2>&1 || rc=$?
    check "empty username rejected" test "${rc}" -ne 0
    rc=0; system::users::modify bob "" /bin/bash >/dev/null 2>&1 || rc=$?
    check "empty field rejected" test "${rc}" -ne 0
    rc=0; system::users::modify bob shell "" >/dev/null 2>&1 || rc=$?
    check "empty value rejected" test "${rc}" -ne 0
    rc=0; system::users::modify bob shell /bin/bash >/dev/null 2>&1 || rc=$?
    check "unknown user rejected" test "${rc}" -ne 0
    eq "0" "$(grep -c '^usermod ' "${SANDBOX}/calls" || true)" "usermod never called on bad input"
    sandbox_drop

    testframework::section "modify: неизвестное поле / unknown field"
    sandbox_new
    fake usermod 0
    fake id 0
    rc=0; system::users::modify bob bogus x >/dev/null 2>&1 || rc=$?
    check "unknown field rejected" test "${rc}" -ne 0
    eq "0" "$(grep -c '^usermod ' "${SANDBOX}/calls" || true)" "usermod never called on an unknown field"
    sandbox_drop

    testframework::section "modify: маппинг полей / field mapping"
    sandbox_new
    fake usermod 0
    # id: bob существует, остальных нет / id: bob exists, the rest do not
    rm -f "${SANDBOX}/bin/id"
    printf '#!/bin/bash\n[ "$1" = "bob" ]\n' > "${SANDBOX}/bin/id"
    "${REAL_CHMOD}" +x "${SANDBOX}/bin/id"
    system::users::modify bob name bob2 >/dev/null 2>&1
    system::users::modify bob home /home/bob2 >/dev/null 2>&1
    system::users::modify bob shell /bin/bash >/dev/null 2>&1
    system::users::modify bob gecos Bob >/dev/null 2>&1
    system::users::modify bob group sudo >/dev/null 2>&1
    check "name -> -l"   grep -qx 'usermod -l bob2 bob' "${SANDBOX}/calls"
    check "home -> -d"   grep -qx 'usermod -d /home/bob2 bob' "${SANDBOX}/calls"
    check "shell -> -s"  grep -qx 'usermod -s /bin/bash bob' "${SANDBOX}/calls"
    check "gecos -> -c"  grep -qx 'usermod -c Bob bob' "${SANDBOX}/calls"
    check "group -> -g"  grep -qx 'usermod -g sudo bob' "${SANDBOX}/calls"
    sandbox_drop

    testframework::section "modify: переименование в занятое имя / rename conflict"
    sandbox_new
    fake usermod 0
    fake id 0
    rc=0; system::users::modify bob name bob2 >/dev/null 2>&1 || rc=$?
    check "rename onto an existing name rejected" test "${rc}" -ne 0
    eq "0" "$(grep -c '^usermod ' "${SANDBOX}/calls" || true)" "usermod never called on a rename conflict"
    sandbox_drop

    testframework::section "modify: нет usermod / no usermod"
    sandbox_new
    fake id 0
    rc=0; system::users::modify bob shell /bin/bash >/dev/null 2>&1 || rc=$?
    check "missing usermod rejected" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "group_info / информация о группе"
    sandbox_new
    fake getent 0 'sudo:x:27:alice,bob'
    out="$(system::users::group_info sudo)"
    eq "gid: 27"$'\n'"members: alice,bob" "${out}" "gid and members"
    sandbox_drop

    sandbox_new
    fake getent 0 'nogroup:x:65534:'
    out="$(system::users::group_info nogroup)"
    eq "gid: 65534"$'\n'"members:" "${out}" "empty members"
    sandbox_drop

    sandbox_new
    fake getent 1
    rc=0; system::users::group_info sudo >/dev/null 2>&1 || rc=$?
    check "missing group rejected" test "${rc}" -ne 0
    rc=0; system::users::group_info "" >/dev/null 2>&1 || rc=$?
    check "empty group name rejected" test "${rc}" -ne 0
    sandbox_drop

    testframework::summary
}

main "$@"
