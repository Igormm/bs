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

    testframework::section "render/apply / рендер и применение"
    SSHD_WZ_VALUES[Port]="2222"
    local cfg; cfg="$(sshd_wz::render_config)"
    testframework::assert_command "printf '%s' '${cfg}' | grep -q '^Port 2222$'" "render_config includes Port"
    SSHD_WZ_TARGET="print"; SSHD_WZ_VIEW="params"
    sshd_wz::apply
    testframework::assert_equal "preview" "${SSHD_WZ_VIEW}" "print target switches to preview"
    tui::modal::close

    testframework::section "match render / match в конфиге"
    SSHD_WZ_VALUES[ChrootDirectory]="%h"
    SSHD_WZ_VALUES[ForceCommand]="internal-sftp"
    cfg="$(sshd_wz::render_config)"
    testframework::assert_command "printf '%s' '${cfg}' | grep -q '^Match '" "match header rendered"
    testframework::assert_command "printf '%s' '${cfg}' | grep -q '^    ChrootDirectory %h$'" "chroot inside match"

    testframework::section "target/confirm / цель и подтверждение"
    SSHD_WZ_TARGET="dropin"
    sshd_wz::cycle_target
    testframework::assert_equal "main" "${SSHD_WZ_TARGET}" "cycle dropin→main"
    sshd_wz::cycle_target
    testframework::assert_equal "print" "${SSHD_WZ_TARGET}" "cycle main→print"
    sshd_wz::cycle_target
    testframework::assert_equal "dropin" "${SSHD_WZ_TARGET}" "cycle print→dropin"

    local aftmp; aftmp="$(mktemp -d)"
    export BS_SSHD_DIR="${aftmp}" BS_SSHD_DROPIN="99-bs.conf" BS_SSHD_BIN="/bin/true"
    SSHD_WZ_TARGET="dropin"
    sshd_wz::apply
    testframework::assert_equal "confirm" "$(tui::modal::top)" "apply opens confirm modal"
    testframework::assert_true "! -f '${aftmp}/99-bs.conf'" "nothing written before confirm"
    tui::modal::close
    rm -rf "${aftmp}"

    testframework::section "focus / фокус панелей"
    SSHD_WZ_FOCUS="params"
    TUI_KEY="LEFT"; sshd_wz::handle_view_key
    testframework::assert_equal "menu" "${SSHD_WZ_FOCUS}" "LEFT focuses menu"
    TUI_KEY="RIGHT"; sshd_wz::handle_view_key
    testframework::assert_equal "params" "${SSHD_WZ_FOCUS}" "RIGHT focuses params"

    testframework::section "menu navigation / навигация меню"
    SSHD_WZ_FOCUS="menu"
    SSHD_WZ_SECTION=0; sshd_wz::load_names
    TUI_KEY="DOWN"; sshd_wz::handle_view_key
    testframework::assert_equal "1" "${SSHD_WZ_SECTION}" "menu DOWN moves section"
    testframework::assert_equal "PermitRootLogin" "${SSHD_WZ_NAMES[0]}" "params reloaded for new section"

    testframework::section "single border / одинарная рамка"
    sshd_wz::draw
    testframework::assert_equal "┌" "${TUI_BORDER_TL}" "single border set"
    local has_double=0 key2
    for key2 in "${!TUI_BUF[@]}"; do [[ "${TUI_BUF[$key2]}" == "╔" ]] && has_double=1; done
    testframework::assert_equal "0" "${has_double}" "no double border chars"

    testframework::section "set -u isolation / изоляция set -u"
    local iso
    iso="$(bash -c '
        unset BASH_EXECUTION_STRING BS_INITIALIZED
        source "$1/bootstrap/init.sh"
        bs::strict
        export BS_HOME="$1"
        source "$1/examples/sshd_wizard.sh"
        TUI_COLS=100 TUI_LINES=30
        sshd_wz::load_sections; sshd_wz::load_names; sshd_wz::paint_all
        for k in LEFT RIGHT UP DOWN; do TUI_KEY="$k"; sshd_wz::handle_view_key || exit 7; done
        printf ok
    ' bash "${BS_PROJECT_ROOT}" 2>&1)"
    testframework::assert_equal "ok" "${iso}" "handler survives set -u without a caller-local i"

    testframework::summary
}

main "$@"
