#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testdevicestuiunit.sh — unit tests for examples/devices_tui (sourced, no main)
# tests/unit/testdevicestuiunit.sh — юнит-тесты examples/devices_tui (source без main)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/tui/tui"
load "lib/system/devicectl"

T=""

# Мок драйвера / mock driver
driver::mock::detect()   { printf 'm1\tMock Mouse\tpointer\nm2\tMock Pad\ttouchpad\n'; }
driver::mock::params()   {
    printf 'speed\trange:-1.0:1.0:0.05\t0.0\t0.0\t\ttip\n'
    printf 'natural_scroll\tbool\t0\t0\t\t\n'
    printf 'accel\tenum:low,med,high\tmed\tmed\tlow,med,high\t\n'
}
driver::mock::get()      { [[ "$2" == "speed" ]] && { printf '0.0'; return 0; }; return "${E_INVALID}"; }
driver::mock::set()      { printf 'set:%s:%s:%s\n' "$1" "$2" "$3" >> "${T}/setlog"; return 0; }
driver::mock::snapshot() { printf 'speed\t0.0\n'; }

main() {
    print_header "devices_tui Unit Tests / Юнит-тесты devices_tui"
    testframework::init

    T="$(mktemp -d)"
    export BS_PROFILE_DIR="${T}/prof"
    export DEVICECTL_BACKEND="none"
    DEVICECTL_DRIVERS=(mock)

    source "${BS_PROJECT_ROOT}/examples/devices_tui.sh"

    testframework::section "state / состояние"
    testframework::assert_command "is::function dtui::reload" "TUI reload function defined"
    testframework::assert_command "is::function dtui::key" "TUI key dispatch function defined"
    dtui::reload
    testframework::assert_equal "2" "${#DEVICES[@]}" "reload lists mock devices"
    dtui::selected
    testframework::assert_equal "mock" "${DEV_DRIVER}" "selected driver"
    testframework::assert_equal "Mock Mouse" "${DEV_LABEL}" "selected label"
    testframework::assert_equal "" "${MODAL}" "no modal initially"

    testframework::section "params load / загрузка параметров"
    dtui::load_params
    testframework::assert_equal "3" "${#PARAMS[@]}" "3 params loaded"

    testframework::section "draw fills buffer / отрисовка заполняет буфер"
    export TUI_COLS=100 TUI_LINES=30
    tui::buf::clear
    dtui::draw_list
    testframework::assert_true "${#TUI_BUF[@]} -gt 0" "draw_list fills TUI_BUF"
    tui::buf::clear
    dtui::draw_params
    testframework::assert_true "${#TUI_BUF[@]} -gt 0" "draw_params fills TUI_BUF"
    tui::buf::clear
    SCR=2
    dtui::draw_review
    testframework::assert_true "${#TUI_BUF[@]} -gt 0" "draw_review fills TUI_BUF"

    testframework::section "collect / сбор снимков"
    local collected=0
    grep -qF "$(printf 'mock\tm1\tspeed')" <<< "$( dtui::collect )" && collected=1
    testframework::assert_equal "1" "${collected}" "collect builds save TSV"

    testframework::section "navigation / навигация"
    SCR=0; SEL=0
    dtui::key DOWN
    testframework::assert_equal "1" "${SEL}" "DOWN selects second device"
    dtui::key DOWN
    testframework::assert_equal "1" "${SEL}" "DOWN clamps at last"
    dtui::key UP
    testframework::assert_equal "0" "${SEL}" "UP moves back"
    dtui::key UP
    testframework::assert_equal "0" "${SEL}" "UP clamps at first"
    dtui::key ENTER
    testframework::assert_equal "1" "${SCR}" "ENTER opens params screen"
    testframework::assert_equal "0" "${PSEL}" "PSEL reset on open"
    dtui::key DOWN
    testframework::assert_equal "1" "${PSEL}" "DOWN moves param selection"
    dtui::key DOWN
    testframework::assert_equal "2" "${PSEL}" "DOWN to last param"
    dtui::key DOWN
    testframework::assert_equal "2" "${PSEL}" "param DOWN clamps at last"
    dtui::key RIGHT
    testframework::assert_equal "2" "${SCR}" "RIGHT opens review"
    dtui::key LEFT
    testframework::assert_equal "1" "${SCR}" "LEFT back to params"
    dtui::key LEFT
    testframework::assert_equal "0" "${SCR}" "LEFT back to list"
    local rc=0
    dtui::key q || rc=$?
    testframework::assert_equal "1" "${rc}" "q requests quit"

    testframework::section "edit bool / правка bool"
    SCR=1; PSEL=1
    dtui::key ENTER
    testframework::assert_equal "OK: natural_scroll=1" "${STATUS}" "bool toggles and applies"
    testframework::assert_command "grep -Fqx 'set:m1:natural_scroll:1' '${T}/setlog'" "bool replayed through device::set"

    testframework::section "edit enum / правка enum"
    SCR=1; PSEL=2
    dtui::key ENTER
    testframework::assert_equal "picker" "${MODAL}" "enum opens picker"
    testframework::assert_equal "3" "${#MO_VALS[@]}" "picker has 3 choices"
    dtui::key DOWN
    testframework::assert_equal "1" "${MO_SEL}" "picker DOWN selects second"
    dtui::key DOWN
    testframework::assert_equal "2" "${MO_SEL}" "picker DOWN to last"
    dtui::key DOWN
    testframework::assert_equal "2" "${MO_SEL}" "picker DOWN clamps at last"
    dtui::key UP
    testframework::assert_equal "1" "${MO_SEL}" "picker UP moves back"
    dtui::key ENTER
    testframework::assert_equal "" "${MODAL}" "picker ENTER closes modal"
    testframework::assert_equal "OK: accel=med" "${STATUS}" "enum value applied"
    testframework::assert_command "grep -Fqx 'set:m1:accel:med' '${T}/setlog'" "enum replayed through device::set"

    testframework::section "edit enum cancel / отмена enum"
    SCR=1; PSEL=2
    dtui::key ENTER
    dtui::key ESC
    testframework::assert_equal "" "${MODAL}" "picker ESC cancels without apply"

    testframework::section "edit manual / ручной ввод"
    SCR=1; PSEL=0
    dtui::key ENTER
    testframework::assert_equal "input" "${MODAL}" "range opens input modal"
    testframework::assert_equal "speed" "${MO_TARGET}" "input targets the param"
    testframework::assert_equal "0.0" "${MO_VALUE}" "input prefilled with default"
    dtui::key BACKSPACE
    testframework::assert_equal "0." "${MO_VALUE}" "backspace removes a char"
    dtui::key LEFT
    testframework::assert_equal "1" "${MO_CURSOR}" "LEFT moves cursor"
    dtui::key x
    testframework::assert_equal "0x." "${MO_VALUE}" "char inserted at cursor"
    dtui::key ESC
    testframework::assert_equal "" "${MODAL}" "ESC cancels input"
    testframework::assert_command "! grep -q 'set:m1:speed' '${T}/setlog'" "cancel leaves device untouched"

    dtui::key ENTER
    testframework::assert_equal "input" "${MODAL}" "ENTER reopens input"
    dtui::key .
    dtui::key ENTER
    testframework::assert_equal "" "${MODAL}" "ENTER applies and closes"
    testframework::assert_equal "OK: speed=0.0." "${STATUS}" "manual value applied"
    testframework::assert_command "grep -Fqx 'set:m1:speed:0.0.' '${T}/setlog'" "manual replayed through device::set"

    testframework::section "profile save/apply / профиль"
    SCR=2
    dtui::key s
    testframework::assert_equal "input" "${MODAL}" "s opens save input"
    testframework::assert_equal "profile save" "${MO_TARGET}" "save target"
    local ch
    for ch in d e m o; do dtui::key "${ch}"; done
    testframework::assert_equal "demo" "${MO_VALUE}" "profile name typed"
    dtui::key ENTER
    testframework::assert_equal "demo" "${ACTIVE_PROFILE}" "active profile set on save"
    testframework::assert_file_exists "${T}/prof/demo.conf" "profile file written"
    testframework::assert_command "grep -Fqx '# BEGIN bs-devices' '${T}/prof/demo.conf'" "profile marker written"

    dtui::key a
    testframework::assert_equal "input" "${MODAL}" "a opens apply input"
    testframework::assert_equal "profile apply" "${MO_TARGET}" "apply target"
    testframework::assert_equal "demo" "${MO_VALUE}" "apply prefilled with active profile"
    dtui::key ENTER
    testframework::assert_equal "" "${MODAL}" "apply closes modal"
    testframework::assert_true "'${STATUS}' == *'profile applied: demo'*" "apply status set"

    testframework::section "draw modals / отрисовка модалок"
    MODAL="input"; MO_TARGET="x"; MO_VALUE="abc"; MO_CURSOR=3
    tui::buf::clear
    dtui::draw_input
    testframework::assert_true "${#TUI_BUF[@]} -gt 0" "draw_input fills TUI_BUF"
    MODAL="picker"; MO_VALS=( low med high ); MO_SEL=1; EDIT_PARAM="accel"
    tui::buf::clear
    dtui::draw_picker
    testframework::assert_true "${#TUI_BUF[@]} -gt 0" "draw_picker fills TUI_BUF"

    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
