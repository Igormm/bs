#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testpointersunit.sh — unit tests for lib/system/pointers (driver)
# tests/unit/testpointersunit.sh — юнит-тесты lib/system/pointers (драйвер)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

T=""

main() {
    print_header "pointers Unit Tests / Юнит-тесты pointers"
    testframework::init
    T="$(mktemp -d)"

    # Шим xinput / xinput shim
    mkdir -p "${T}/shim"
    cat > "${T}/shim/xinput" <<'EOF'
#!/bin/sh
if [ "$1 $2" = "list --name-only" ]; then
    printf 'Synaptics TouchPad\nLogicool Trackball\nTPPS/2 IBM TrackPoint\n'
elif [ "$1" = "set-prop" ]; then
    printf '%s\n' "$*" >> "${XINPUT_LOG}"
    exit 0
elif [ "$1" = "list-props" ]; then
    printf '\tlibinput Accel Speed (336):\t0.500000\n'
fi
EOF
    chmod +x "${T}/shim/xinput"
    export XINPUT_LOG="${T}/calls.log"

    export DRIVER_POINTERS_XINPUT="${T}/shim/xinput"
    export DEVICECTL_BACKEND="x11"
    export DRIVER_POINTERS_SENS_PATH="${T}/sens"
    printf '128\n' > "${T}/sens"

    load "lib/system/pointers"

    testframework::section "detect / детект"
    local out opens=0
    out="$(driver::pointers::detect)"
    grep -q 'touchpad' <<< "${out}" && opens=1
    testframework::assert_equal "1" "${opens}" "detect finds touchpad"
    grep -q 'trackball' <<< "${out}" && opens=1
    testframework::assert_equal "1" "${opens}" "detect finds trackball"
    grep -q 'trackpoint' <<< "${out}" && opens=1
    testframework::assert_equal "1" "${opens}" "detect finds trackpoint"
    testframework::assert_equal "touchpad" "$(driver::pointers::__kind 'Synaptics TouchPad')" "kind: touchpad"
    testframework::assert_equal "trackball" "$(driver::pointers::__kind 'Logicool Trackball')" "kind: trackball"
    testframework::assert_equal "trackpoint" "$(driver::pointers::__kind 'TPPS/2 IBM TrackPoint')" "kind: trackpoint"
    testframework::assert_equal "pointer" "$(driver::pointers::__kind 'Generic USB Mouse')" "kind: generic pointer"

    testframework::section "params / параметры"
    local has_sens=0 has_tap=0
    grep -q $'^sens\t' <<< "$(driver::pointers::params 'TPPS/2 IBM TrackPoint')" && has_sens=1
    testframework::assert_equal "1" "${has_sens}" "trackpoint has sens"
    grep -q $'^tap_to_click\t' <<< "$(driver::pointers::params 'Synaptics TouchPad')" && has_tap=1
    testframework::assert_equal "1" "${has_tap}" "touchpad has tap_to_click"

    testframework::section "get / чтение"
    testframework::assert_equal "0.500000" "$(driver::pointers::get 'Logicool Trackball' speed)" "get speed via xinput list-props"
    testframework::assert_equal "128" "$(driver::pointers::get 'TPPS/2 IBM TrackPoint' sens)" "get sens via sysfs"

    testframework::section "set / применение (X11)"
    local rc=0
    driver::pointers::set 'Logicool Trackball' speed 0.4 || rc=$?
    testframework::assert_equal "0" "${rc}" "set speed ok"
    testframework::assert_command "grep -Fq 'libinput Accel Speed' '${XINPUT_LOG}'" "speed maps to libinput Accel Speed"
    rc=0; driver::pointers::set 'Synaptics TouchPad' natural_scroll true || rc=$?
    testframework::assert_equal "0" "${rc}" "set natural_scroll ok"
    testframework::assert_command "grep -Fq 'libinput Natural Scrolling Enabled' '${XINPUT_LOG}'" "natural_scroll maps property"
    rc=0; driver::pointers::set 'TPPS/2 IBM TrackPoint' sens 160 || rc=$?
    testframework::assert_equal "0" "${rc}" "set sens ok"
    testframework::assert_equal "160" "$(cat "${T}/sens")" "sens written to sysfs"

    testframework::section "snapshot / снимок"
    local has_speed=0
    grep -q $'^speed\t' <<< "$(driver::pointers::snapshot 'TPPS/2 IBM TrackPoint')" && has_speed=1
    testframework::assert_equal "1" "${has_speed}" "snapshot has params"

    testframework::section "degradation / деградация"
    DEVICECTL_BACKEND="none"
    rc=0; driver::pointers::set 'Logicool Trackball' speed 0.4 2>/dev/null || rc=$?
    testframework::assert_equal "102" "${rc}" "no backend -> LIB_ERROR_PLATFORM_UNSUPPORTED"
    rc=0; driver::pointers::set 'Generic USB Mouse' sens 9 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "sens on non-trackpoint -> E_INVALID"

    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
