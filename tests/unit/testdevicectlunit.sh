#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testdevicectlunit.sh — unit tests for lib/system/devicectl (engine)
# tests/unit/testdevicectlunit.sh — юнит-тесты lib/system/devicectl (движок)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/system/devicectl"

# Моки драйвера / mock driver (detect уже определён — загрузка файла не нужна,
# is::function short-circuits device::load)
driver::mock::detect()   { printf 'm1\tMock Mouse\tpointer\n'; }
driver::mock::params()   { printf 'speed\trange:-1.0:1.0:0.05\t0.0\t0.0\t\ttip\n'; }
driver::mock::get()      { [[ "$1" == "m1" && "$2" == "speed" ]] && { printf '0.0'; return 0; }; return "${E_INVALID}"; }
driver::mock::set()      { [[ "$1" == "m1" && "$2" == "speed" ]] && return 0; return "${E_INVALID}"; }
driver::mock::snapshot() { printf 'speed\t0.0\n'; }

main() {
    print_header "devicectl Unit Tests / Юнит-тесты devicectl"
    testframework::init

    testframework::section "default registry / реестр по умолчанию"
    local has_ptr=0 has_kb=0 has_loc=0 d
    for d in "${DEVICECTL_DRIVERS[@]}"; do
        [[ "$d" == "pointers" ]] && has_ptr=1
        [[ "$d" == "keyboard" ]] && has_kb=1
        [[ "$d" == "locale" ]] && has_loc=1
    done
    testframework::assert_equal "1" "${has_ptr}" "pointers registered by default"
    testframework::assert_equal "1" "${has_kb}" "keyboard registered by default"
    testframework::assert_equal "1" "${has_loc}" "locale registered by default"

    testframework::section "backend / бэкенд"
    local out
    out="$( ( DEVICECTL_BACKEND= DISPLAY= XDG_SESSION_TYPE=wayland; device::backend ) )"
    testframework::assert_equal "wayland" "${out}" "wayland from XDG_SESSION_TYPE"
    out="$( ( DEVICECTL_BACKEND= DISPLAY=:0 XDG_SESSION_TYPE= WAYLAND_DISPLAY=; device::backend ) )"
    testframework::assert_equal "x11" "${out}" "x11 from DISPLAY"
    out="$( ( DEVICECTL_BACKEND= DISPLAY= XDG_SESSION_TYPE= WAYLAND_DISPLAY=; device::backend ) )"
    testframework::assert_equal "none" "${out}" "none when nothing set"

    testframework::section "registry / реестр"
    device::registry mock
    device::registry mock        # дубль не добавляется / duplicate skipped
    local -i n=0
    for d in "${DEVICECTL_DRIVERS[@]}"; do [[ "$d" == "mock" ]] && n=$(( n + 1 )); done
    testframework::assert_equal "1" "${n}" "registry dedupes"

    testframework::section "dispatch / диспетчеризация"
    local list1 has_mouse=0 has_pointer=0
    list1="$(device::list mock)"
    grep -q 'Mock Mouse' <<< "${list1}" && has_mouse=1
    testframework::assert_equal "1" "${has_mouse}" "list returns the label"
    grep -q 'pointer' <<< "${list1}" && has_pointer=1
    testframework::assert_equal "1" "${has_pointer}" "list returns the kind"
    local p1
    p1="$(device::params mock m1)"
    testframework::assert_true "'${p1}' == *'speed'*'range:-1.0:1.0:0.05'*" "params dispatch"
    testframework::assert_equal "0.0" "$(device::get mock m1 speed)" "get dispatch"
    local rc=0
    device::set mock m1 speed 0.4 || rc=$?
    testframework::assert_equal "0" "${rc}" "set dispatch ok"

    testframework::section "unknown handle/param / неизвестное"
    rc=0; device::get mock nohandle speed || rc=$?
    testframework::assert_equal "2" "${rc}" "unknown handle -> E_INVALID"
    rc=0; device::set mock m1 nope 1 || rc=$?
    testframework::assert_equal "2" "${rc}" "unknown param -> E_INVALID"
    rc=0; device::params nosuchdriver x || rc=$?
    testframework::assert_equal "2" "${rc}" "unknown driver -> E_INVALID"

    testframework::section "snapshot / снимок"
    testframework::assert_equal "speed	0.0" "$(device::snapshot mock m1)" "snapshot dispatch"

    testframework::summary
}

main "$@"
