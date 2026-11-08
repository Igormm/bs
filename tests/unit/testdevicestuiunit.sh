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

# Мок драйвера / mock driver
driver::mock::detect()   { printf 'm1\tMock Mouse\tpointer\nm2\tMock Pad\ttouchpad\n'; }
driver::mock::params()   { printf 'speed\trange:-1.0:1.0:0.05\t0.0\t0.0\t\ttip\n'; }
driver::mock::get()      { [[ "$2" == "speed" ]] && { printf '0.0'; return 0; }; return "${E_INVALID}"; }
driver::mock::set()      { return 0; }
driver::mock::snapshot() { printf 'speed\t0.0\n'; }

main() {
    print_header "devices_tui Unit Tests / Юнит-тесты devices_tui"
    testframework::init

    export DEVICECTL_BACKEND="none"
    DEVICECTL_DRIVERS=(mock)

    source "${BS_PROJECT_ROOT}/examples/devices_tui.sh"

    testframework::section "state / состояние"
    testframework::assert_command "is::function dtui::reload" "TUI reload function defined"
    dtui::reload
    testframework::assert_equal "2" "${#DEVICES[@]}" "reload lists mock devices"
    dtui::selected
    testframework::assert_equal "mock" "${DEV_DRIVER}" "selected driver"
    testframework::assert_equal "Mock Mouse" "${DEV_LABEL}" "selected label"
    testframework::assert_equal "" "${MODAL}" "no modal initially"

    testframework::section "params load / загрузка параметров"
    dtui::load_params
    testframework::assert_true "${#PARAMS[@]} -gt 0" "params loaded"

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

    testframework::summary
}

main "$@"
