#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testfail2banwizardunit.sh — draw/state tests for the fail2ban wizard
# tests/unit/testfail2banwizardunit.sh — тесты отрисовки/состояния визарда fail2ban

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

source "${BS_PROJECT_ROOT}/examples/fail2ban_wizard.sh"

main() {
    print_header "fail2ban Wizard Unit Tests / Тесты визарда fail2ban"
    testframework::init
    TUI_COLS=120 TUI_LINES=34

    local dt; dt="$(mktemp -d)"
    export BS_FAIL2BAN_DIR="${dt}"
    mkdir -p "${dt}/filter.d"
    touch "${dt}/filter.d/sshd.conf" "${dt}/filter.d/nginx-http-auth.conf"

    testframework::section "jails/sections / джейлы и секции"
    f2b_wz::load_jails
    testframework::assert_true "${#F2B_WZ_JAILS[@]} -ge 2" "jails detected"
    F2B_WZ_JAIL_ON["sshd"]=1
    F2B_WZ_VALUES["sshd.enabled"]="true"
    f2b_wz::rebuild_sections
    testframework::assert_equal "DEFAULT" "${F2B_WZ_SECTIONS[0]}" "first section DEFAULT"
    testframework::assert_equal "sshd" "${F2B_WZ_SECTIONS[1]}" "second section sshd"

    testframework::section "draw / отрисовка"
    f2b_wz::draw
    testframework::assert_equal "${TUI_BORDER_TL}" "${TUI_BUF[1,0]}" "box drawn"
    local rowstr="" c
    for (( c = 0; c < TUI_COLS; c++ )); do rowstr+="${TUI_BUF[2,$c]:-}"; done
    testframework::assert_true "'${rowstr}' == *bantime*" "DEFAULT param on screen"

    testframework::section "render / INI"
    F2B_WZ_VALUES["DEFAULT.maxretry"]="5"
    local cfg; cfg="$(f2b_wz::render_config)"
    testframework::assert_command "printf '%s' '${cfg}' | grep -q '^\[DEFAULT\]$'" "DEFAULT section"
    testframework::assert_command "printf '%s' '${cfg}' | grep -q '^\[sshd\]$'" "sshd section"
    testframework::assert_command "printf '%s' '${cfg}' | grep -q '^maxretry = 5$'" "maxretry in config"

    testframework::section "toggle jail / переключение джейла"
    local before=${#F2B_WZ_SECTIONS[@]}
    F2B_WZ_JAIL_SEL=0
    # find nginx-http-auth index / найти индекс
    local i
    for i in "${!F2B_WZ_JAILS[@]}"; do
        [[ "${F2B_WZ_JAILS[$i]}" == "nginx-http-auth" ]] && F2B_WZ_JAIL_SEL=$i
    done
    f2b_wz::toggle_jail
    testframework::assert_true "${#F2B_WZ_SECTIONS[@]} -gt ${before}" "jail added"
    testframework::assert_equal "true" "${F2B_WZ_VALUES[nginx-http-auth.enabled]:-}" "nginx enabled value"

    testframework::section "profile / профиль"
    f2b_wz::apply_profile strict
    testframework::assert_equal "true" "${F2B_WZ_VALUES[DEFAULT.bantime.increment]:-}" "strict sets increment"
    testframework::assert_equal "1" "${F2B_WZ_JAIL_ON[recidive]:-0}" "strict enables recidive"

    testframework::section "set -u isolation / изоляция set -u"
    local iso
    iso="$(bash -c '
        unset BASH_EXECUTION_STRING BS_INITIALIZED
        source "$1/bootstrap/init.sh"
        bs::strict
        export BS_HOME="$1" BS_FAIL2BAN_DIR="$2"
        source "$1/examples/fail2ban_wizard.sh"
        TUI_COLS=100 TUI_LINES=30
        f2b_wz::load_jails; F2B_WZ_JAIL_ON[sshd]=1; f2b_wz::rebuild_sections; f2b_wz::paint_all
        for k in LEFT RIGHT UP DOWN; do TUI_KEY="$k"; f2b_wz::handle_view_key || exit 7; done
        printf ok
    ' bash "${BS_PROJECT_ROOT}" "${dt}" 2>&1)"
    testframework::assert_equal "ok" "${iso}" "handlers survive set -u"

    rm -rf "${dt}"
    testframework::summary
}

main "$@"
