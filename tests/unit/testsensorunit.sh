#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsensorunit.sh — Unit tests for lib/system/sensor module
# tests/unit/testsensorunit.sh — Модульные тесты модуля lib/system/sensor

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# ==========================================
# Тестовые фикстуры / test fixtures
# ==========================================

# @private little-endian n-байтное число / n-byte little-endian number
__le() {
    local -i v="${1}" n="${2}"
    local -i i b
    for (( i = 0; i < n; i++ )); do
        b=$(( v & 0xff ))
        printf '\\x%02x' "${b}"
        v=$(( v >> 8 ))
    done
}

# @private одна запись input_event (64-бит layout, 24 байта) / one 24-byte record
__record() {
    local -i s="$1" u="$2" t="$3" c="$4" v="$5"
    printf '%b' "$(__le "${s}" 8)$(__le "${u}" 8)$(__le "${t}" 2)$(__le "${c}" 2)$(__le "${v}" 4)"
}

# @private создать фиктивную среду /dev+sysfs / create fake /dev+sysfs
__make_fixture() {
    local -r root="$(mktemp -d)"
    mkdir -p "${root}/input/event9/device/capabilities" "${root}/devinput"
    printf 'TestTouch\n' > "${root}/input/event9/device/name"
    printf 'usb-0000:00:14.0-3/input0\n' > "${root}/input/event9/device/phys"
    printf 'b\n' > "${root}/input/event9/device/capabilities/ev"   # EV_SYN|EV_KEY|EV_ABS
    printf '400 0 0 0 0 0\n' > "${root}/input/event9/device/capabilities/key"  # BTN_TOUCH
    printf '3\n' > "${root}/input/event9/device/capabilities/abs"  # X|Y
    # две записи: ABS_MT_POSITION_X=1234 и SYN value=-5
    { __record 100 500000 3 53 1234; __record 101 600000 0 0 -5; } > "${root}/devinput/event9"
    printf '%s\n' "${root}"
}

# ==========================================
# Тесты / tests
# ==========================================

test_loads() {
    load "lib/system/sensor"
    testframework::assert_true "${SYSTEM_SENSOR_LOADED:-}" "Module loaded"
}

test_record_size() {
    local out
    out="$(SENSOR_EVENT_SIZE=16 sensor::record_size)"
    testframework::assert_equal "16" "${out}" "SENSOR_EVENT_SIZE hook overrides"
    out="$(SENSOR_EVENT_SIZE='' sensor::record_size)"
    testframework::assert_true "'${out}' == 16 || '${out}' == 24" "auto size is 16 or 24"
}

test_names() {
    testframework::assert_equal "EV_ABS" "$(sensor::type_name 3)" "type_name 3"
    testframework::assert_equal "ABS_MT_POSITION_X" "$(sensor::abs_name 53)" "abs_name 53"
    testframework::assert_equal "ABS_60" "$(sensor::abs_name 60)" "abs_name unknown"
    testframework::assert_equal "BTN_TOUCH" "$(sensor::key_name 330)" "key_name 330"
    testframework::assert_equal "ABS_Y" "$(sensor::code_name 3 1)" "code_name dispatch"
}

test_devices_and_info() {
    local -r root="$(__make_fixture)"
    local out
    out="$(SENSOR_INPUT_DIR="${root}/input" sensor::devices)"
    testframework::assert_true "'${out}' == $'event9\tTestTouch'" "devices lists fake"

    out="$(SENSOR_INPUT_DIR="${root}/input" sensor::devices "no-match-xyz" 2>/dev/null)" || true
    testframework::assert_equal "" "${out}" "pattern filter excludes"

    out="$(SENSOR_INPUT_DIR="${root}/input" sensor::info event9)"
    testframework::assert_true '${out} == *"name=TestTouch"*' "info has name"
    testframework::assert_true '${out} == *"capabilities_ev=b"*' "info caps ev"

    local rc=0
    SENSOR_INPUT_DIR="${root}/input" sensor::info event404 >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "info missing device code"
    rm -rf "${root}"
}

test_capabilities_decode() {
    local -r root="$(__make_fixture)"
    local out
    out="$(SENSOR_INPUT_DIR="${root}/input" sensor::capabilities event9 ev)"
    testframework::assert_true '${out} == *EV_ABS*' "ev decoded"
    out="$(SENSOR_INPUT_DIR="${root}/input" sensor::capabilities event9 key)"
    testframework::assert_true '${out} == *BTN_TOUCH*' "BTN_TOUCH bit 330 decoded"
    out="$(SENSOR_INPUT_DIR="${root}/input" sensor::capabilities event9 abs)"
    testframework::assert_true '${out} == *ABS_X* && ${out} == *ABS_Y*' "abs X,Y decoded"
    rm -rf "${root}"
}

test_events_decode() {
    local -r root="$(__make_fixture)"
    local -a lines=()
    mapfile -t lines < <(SENSOR_DEV_DIR="${root}/devinput" SENSOR_INPUT_DIR="${root}/input" SENSOR_EVENT_SIZE=24 sensor::events event9)
    testframework::assert_equal "2" "${#lines[@]}" "two records decoded"
    testframework::assert_equal "100 500000 3 53 1234" "${lines[0]:-}" "ABS event decoded"
    testframework::assert_equal "101 600000 0 0 -5" "${lines[1]:-}" "negative s32 decoded"

    local rc=0
    SENSOR_DEV_DIR="${root}/nope" sensor::events event9 >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_PERMISSION_DENIED}" "${rc}" "unreadable device code"
    rm -rf "${root}"
}

test_detect() {
    local -r root="$(__make_fixture)"
    local out rc=0
    out="$(SENSOR_DEV_DIR="${root}/devinput" SENSOR_INPUT_DIR="${root}/input" SENSOR_EVENT_SIZE=24 sensor::detect event9 2)" || rc=$?
    testframework::assert_equal "${E_SUCCESS}" "${rc}" "detect sees event from fixture"
    testframework::assert_equal "100 500000 3 53 1234" "${out}" "detect prints first line"
    rm -rf "${root}"
}

test_diagnose_fixture() {
    local -r root="$(__make_fixture)"
    local out rc=0
    out="$(SENSOR_DEV_DIR="${root}/devinput" SENSOR_INPUT_DIR="${root}/input" SENSOR_EVENT_SIZE=24 sensor::diagnose event9 1 2>&1)" || rc=$?
    testframework::assert_equal "${E_SUCCESS}" "${rc}" "diagnose passes on healthy fixture"
    testframework::assert_true '${out} == *"[PASS] EV_ABS"*' "diagnose EV_ABS"
    testframework::assert_true '${out} == *BTN_TOUCH*' "diagnose BTN_TOUCH"
    testframework::assert_true '${out} == *"поток событий: 2"*' "diagnose live window counted"
    testframework::assert_true '${out} == *"наблюдалось 1234..1234 (1)"*' "stuck axis detected"
    rm -rf "${root}"
}

test_real_device_graceful() {
    # На хосте без /dev/input или без прав — чистая деградация / graceful on hosts w/o access
    load "lib/system/sensor"
    local rc=0
    sensor::check event0 >/dev/null 2>&1 || rc=$?
    if (( rc != 0 )); then
        testframework::assert_true "${rc} == ${LIB_ERROR_FILE_NOT_FOUND} || ${rc} == ${LIB_ERROR_PERMISSION_DENIED}" \
            "check degrades with a defined code (no /dev/input or perms)"
    else
        testframework::assert_equal "0" "${rc}" "check succeeds on a real readable device"
    fi
}

# ==========================================
# Main
# ==========================================

main() {
    print_header "Sensor Module Unit Tests"
    testframework::init
    load "lib/system/sensor"

    testframework::section "Loading"
    test_loads

    testframework::section "Record size & names"
    test_record_size
    test_names

    testframework::section "Discovery & info"
    test_devices_and_info

    testframework::section "Capabilities"
    test_capabilities_decode

    testframework::section "Events decoding"
    test_events_decode

    testframework::section "Detect"
    test_detect

    testframework::section "Diagnostics"
    test_diagnose_fixture

    testframework::section "Real device graceful degradation"
    test_real_device_graceful

    testframework::summary
}

main "$@"
