#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testdevprofileunit.sh — unit tests for lib/system/devprofile
# tests/unit/testdevprofileunit.sh — юнит-тесты lib/system/devprofile

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

T=""
export BS_PROFILE_DIR=""   # задаётся в main до load / set in main before load

# Мок драйвера для apply / mock driver for apply
driver::mock::detect()   { printf 'm1\tMock Mouse\tpointer\n'; }
driver::mock::params()   { printf 'speed\trange:-1.0:1.0:0.05\t0.0\t0.0\t\ttip\n'; }
driver::mock::get()      { [[ "$1" == "m1" && "$2" == "speed" ]] && { printf '0.0'; return 0; }; return "${E_INVALID}"; }
driver::mock::set()      { printf 'set:%s:%s:%s\n' "$1" "$2" "$3" >> "${T}/setlog"; return 0; }
driver::mock::snapshot() { printf 'speed\t0.0\n'; }

main() {
    print_header "devprofile Unit Tests / Юнит-тесты devprofile"
    testframework::init
    T="$(mktemp -d)"
    export BS_PROFILE_DIR="${T}/prof"

    load "lib/system/devicectl"
    load "lib/system/devprofile"
    device::registry mock

    testframework::section "save / сохранение"
    printf 'pointers\tm1\tspeed\t0.4\n' | devprofile::save demo
    testframework::assert_file_exists "${T}/prof/demo.conf" "profile file created"
    testframework::assert_command "grep -Fqx '[pointers:m1]' '${T}/prof/demo.conf'" "section head written"
    testframework::assert_command "grep -Fqx 'speed=0.4' '${T}/prof/demo.conf'" "value line written"
    testframework::assert_command "grep -Fqx '# BEGIN bs-devices' '${T}/prof/demo.conf'" "begin marker"
    testframework::assert_command "grep -Fqx '# END bs-devices' '${T}/prof/demo.conf'" "end marker"
    testframework::assert_equal "demo" "$(devprofile::active)" "active profile set on save"

    testframework::section "list / список"
    printf 'pointers\tm1\tnatural_scroll\t0\n' | devprofile::save second
    testframework::assert_equal "demo" "$(devprofile::list | sort | head -1)" "list returns a name"

    testframework::section "load / загрузка"
    local load_out
    printf 'pointers\tm1\tspeed\t0.4\n' | devprofile::save lo
    load_out="$(devprofile::load lo)"
    testframework::assert_equal "pointers	m1	speed	0.4" "${load_out}" "load round-trips TSV"

    testframework::section "empty value + unknown section skipped / пропуски"
    printf 'pointers\tm1\temptyv\t\npointers\tm1\tgoodv\t1\n' | devprofile::save skip
    testframework::assert_command "! grep -q 'emptyv' '${T}/prof/skip.conf'" "empty value not written"
    printf 'garbage line\n[x:y]\na=b\n' > "${T}/prof/garb.conf"
    testframework::assert_equal "" "$(devprofile::load garb)" "unmanaged file yields nothing"

    testframework::section "apply / применение"
    printf 'mock\tm1\tspeed\t0.41\n' | devprofile::save app
    local rc=0
    devprofile::apply app 2>/dev/null || rc=$?
    testframework::assert_equal "0" "${rc}" "apply ok"
    testframework::assert_command "grep -Fqx 'set:m1:speed:0.41' '${T}/setlog'" "apply replayed device::set"

    testframework::section "remove / удаление"
    devprofile::remove demo
    testframework::assert_command "! test -e '${T}/prof/demo.conf'" "profile removed"

    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
