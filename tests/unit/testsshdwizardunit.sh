#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsshdwizardunit.sh — draw/state tests for examples/sshd_wizard
# tests/unit/testsshdwizardunit.sh — тесты отрисовки/состояния визарда

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

source "${BS_PROJECT_ROOT}/examples/sshd_wizard.sh"

main() {
    print_header "SSHd Wizard Unit Tests / Тесты визарда sshd"
    testframework::init
    TUI_COLS=100 TUI_LINES=30

    testframework::section "sections/names / секции и параметры"
    sshd_wz::load_sections
    testframework::assert_true "${#SSHD_WZ_SECTIONS[@]} -ge 6" "sections loaded"
    SSHD_WZ_SECTION=0
    sshd_wz::load_names
    testframework::assert_true "${#SSHD_WZ_NAMES[@]} -gt 0" "names loaded for first section"

    testframework::section "draw / отрисовка буфера"
    tui::buf::clear
    sshd_wz::draw
    testframework::assert_equal "${TUI_BORDER_TL}" "${TUI_BUF[1,0]}" "section box drawn"
    local rowstr="" c
    for (( c = 0; c < TUI_COLS; c++ )); do rowstr+="${TUI_BUF[2,$c]:-}"; done
    testframework::assert_true "'${rowstr}' == *Port*" "param name on screen"

    tui::buf::clear
    sshd_wz::draw_desc
    local joined=""
    for key in "${!TUI_BUF[@]}"; do joined+="${TUI_BUF[$key]}"; done
    testframework::assert_true "'${joined}' == *а*" "desc pane has Russian text"

    testframework::section "profile fill / заполнение профиля"
    sshd_wz::apply_profile strict
    testframework::assert_equal "no" "${SSHD_WZ_VALUES[PasswordAuthentication]:-}" "strict fills PasswordAuthentication=no"

    testframework::section "edit modal / модалка правки"
    SSHD_WZ_SECTION=0; sshd_wz::load_names
    local idx=-1 i
    for (( i = 0; i < ${#SSHD_WZ_NAMES[@]}; i++ )); do
        [[ "${SSHD_WZ_NAMES[$i]}" == "Port" ]] && idx=$i
    done
    testframework::assert_true "idx -ge 0" "Port is in Network"
    SSHD_WZ_SELECT="${idx}"
    SSHD_WZ_VALUES[Port]="22"
    sshd_wz::begin_edit
    testframework::assert_equal "edit" "$(tui::modal::top)" "port opens edit modal"
    testframework::assert_equal "input" "${SSHD_WZ_EDIT_MODE}" "port uses input mode"
    testframework::assert_equal "22" "${SSHD_WZ_EDIT_VALUE}" "input seeded with current value"
    tui::modal::close

    SSHD_WZ_EDIT_VALUE="70000"
    SSHD_WZ_EDIT_SEL=0
    sshd_wz::commit_edit
    testframework::assert_true "-n '${SSHD_WZ_EDIT_ERR}'" "invalid value sets error"

    SSHD_WZ_EDIT_VALUE="2222"
    sshd_wz::commit_edit
    testframework::assert_equal "2222" "${SSHD_WZ_VALUES[Port]}" "valid value stored"
    testframework::assert_equal "" "$(tui::modal::top)" "modal closed on commit"

    testframework::summary
}

main "$@"
