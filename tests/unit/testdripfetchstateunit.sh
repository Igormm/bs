#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testdripfetchstateunit.sh — dripfetch clock, calendar and persisted-state regressions
# tests/unit/testdripfetchstateunit.sh — часы, календарь и сохранённое состояние dripfetch

set -euo pipefail

TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_SCRIPT_DIR
BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly BS_PROJECT_ROOT

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"
readonly DRIPFETCH_SCRIPT="${BS_PROJECT_ROOT}/examples/dripfetch.sh"

T=""

run_clock_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        CLOCK_24H=0; CLOCK_SIZE=small; CLOCK_SECONDS=0; CLOCK_DATE=0; CLOCK_AMPM=0
        dripfetch::__time_parts() { NOW_STAMP="13:05:00"; }
        dripfetch::clock_lines
        dripfetch::__time_parts() { NOW_STAMP="01:05:00"; }
        dripfetch::clock_lines
        :
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_clock_12h() {
    local shell_bin="$1" label="$2" rc out
    local prefix="${T}/${label}-clock"
    rc="$(run_clock_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label 12-hour clock probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label 12-hour clock has no diagnostics"
    out="$(<"${prefix}/out")"
    testframework::assert_equal $'1:05 PM\n1:05 AM' "$out" "$label formats both PM and AM"
}

run_hidden_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=20; TERM_H=8; LOGO_NAME=fedora
        BOX_TYPES=(logo sysinfo clock calendar text weather net)
        dripfetch::detect_colour
        dripfetch::layout_boxes
        i=0
        while (( i < 10 )); do
            dripfetch::sel_box
            t=${BOX_TYPES[$SEL_INDEX]}
            printf "%s:%s\n" "$t" "${BOX_VISIBLE[$t]}"
            i=$(( i + 1 ))
        done
        dripfetch::move_sel 1 0
        rc=$?
        printf "move-rc=%s\n" "$rc"
        cat "$POS_FILE"
        :
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_hidden_boxes() {
    local shell_bin="$1" label="$2" rc line selected
    local prefix="${T}/${label}-hidden"
    rc="$(run_hidden_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label hidden-box probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label hidden-box probe has no diagnostics"
    while IFS=':' read -r selected line; do
        [[ "$selected" =~ ^[a-z]+:[01]$ ]] || continue
        testframework::assert_equal "1" "$line" "$label Tab selects only visible boxes"
    done < "${prefix}/out"
    testframework::assert_command "grep -q '^move-rc=0$' '$prefix/out'" "$label moves the visible box without crashing"
    testframework::assert_command "grep -q '^# dripfetch-positions-v2$' '$prefix/out'" "$label persists a versioned positions file"
    testframework::assert_command "grep -q '^logo=' '$prefix/out'" "$label persists the visible box"
    testframework::assert_command "! grep -q '^sysinfo=' '$prefix/out'" "$label does not persist hidden boxes"
}

test_bash_hidden_boxes() {
    assert_hidden_boxes "$(bs::shell::host)" "bash"
}

test_zsh_hidden_boxes() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh hidden boxes" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_hidden_boxes "$zsh_bin" "zsh"
}

run_positions_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=120; TERM_H=40; BOX_TYPES=(logo); LOGO_NAME=fedora
        dripfetch::detect_colour
        dripfetch::layout_boxes
        mkdir -p "$CONFIG_DIR"
        printf "logo=7=3\n" > "$POS_FILE"
        dripfetch::load_positions
        printf "legacy=%s\n" "${BOX_META[logo]}"
        dripfetch::persist_positions
        cat "$POS_FILE"
        BOX_META[logo]="1 1"
        dripfetch::load_positions
        printf "v2=%s\n" "${BOX_META[logo]}"
        printf "# dripfetch-positions-v2\nlogo=0008=0003\n" > "$POS_FILE"
        dripfetch::load_positions
        printf "padded=%s\n" "${BOX_META[logo]}"
        cat "$POS_FILE"
        :
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_positions_migration() {
    local shell_bin="$1" label="$2" rc
    local prefix="${T}/${label}-positions"
    rc="$(run_positions_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label positions probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label positions probe has no diagnostics"
    testframework::assert_command "grep -q '^legacy=3 7$' '$prefix/out'" "$label migrates legacy row/col positions"
    testframework::assert_command "grep -q '^v2=3 7$' '$prefix/out'" "$label reloads v2 col/row positions without another swap"
    testframework::assert_command "grep -q '^# dripfetch-positions-v2$' '$prefix/out'" "$label writes the v2 marker"
    testframework::assert_command "grep -q '^logo=3=7$' '$prefix/out'" "$label persists canonical col/row values"
    testframework::assert_command "grep -q '^padded=8 3$' '$prefix/out'" "$label normalizes leading-zero coordinates as decimal"
}

test_bash_positions_migration() {
    assert_positions_migration "$(bs::shell::host)" "bash"
}

test_zsh_positions_migration() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh positions migration" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_positions_migration "$zsh_bin" "zsh"
}

run_live_collision_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=80; TERM_H=24; BOX_TYPES=(logo clock); LOGO_NAME=fedora
        dripfetch::detect_colour
        dripfetch::layout_boxes
        dripfetch::sel_box
        dripfetch::move_sel 18 0
        printf "logo=%s\nclock=%s\n" "${BOX_META[logo]}" "${BOX_META[clock]}"
        :
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_live_collision() {
    local shell_bin="$1" label="$2" rc
    local prefix="${T}/${label}-live-collision"
    rc="$(run_live_collision_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label live-collision probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label live-collision probe has no diagnostics"
    testframework::assert_command "grep -q '^logo=1 1$' '$prefix/out'" "$label refuses to move a box onto another box"
    testframework::assert_command "grep -q '^clock=19 1$' '$prefix/out'" "$label leaves the other box in place"
}

test_bash_live_collision() {
    assert_live_collision "$(bs::shell::host)" "bash"
}

test_zsh_live_collision() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh live collision" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_live_collision "$zsh_bin" "zsh"
}

run_move_clamp_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=20; TERM_H=8; BOX_TYPES=(logo); LOGO_NAME=fedora
        dripfetch::detect_colour
        dripfetch::layout_boxes
        dripfetch::sel_box
        dripfetch::move_sel 0 100
        m=${BOX_META[logo]}; col=${m%% *}; row=${m#* }
        printf "%s %s %s\n" "$col" "$row" "$(( row + BOX_SLOT_H[logo] - 1 ))"
        :
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_move_clamp() {
    local shell_bin="$1" label="$2" rc col row bottom
    local prefix="${T}/${label}-move-clamp"
    rc="$(run_move_clamp_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label movement-clamp probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label movement-clamp probe has no diagnostics"
    IFS=' ' read -r col row bottom < "${prefix}/out"
    testframework::assert_command "(( $col >= 1 && $row >= 1 && $bottom < 8 ))" "$label movement stays inside the usable area"
}

test_bash_move_clamp() {
    assert_move_clamp "$(bs::shell::host)" "bash"
}

test_zsh_move_clamp() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh movement clamp" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_move_clamp "$zsh_bin" "zsh"
}

run_collision_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=80; TERM_H=24; BOX_TYPES=(logo clock); LOGO_NAME=fedora
        dripfetch::detect_colour
        dripfetch::layout_boxes
        mkdir -p "$CONFIG_DIR"
        printf "# dripfetch-positions-v2\nlogo=999=999\nclock=065=014\n" > "$POS_FILE"
        dripfetch::load_positions
        printf "logo=%s\nclock=%s\n" "${BOX_META[logo]}" "${BOX_META[clock]}"
        :
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_position_collision() {
    local shell_bin="$1" label="$2" rc
    local prefix="${T}/${label}-collision"
    rc="$(run_collision_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label position-collision probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label position-collision probe has no diagnostics"
    testframework::assert_command "grep -q '^logo=64 13$' '$prefix/out'" "$label clamps restored positions to the usable screen"
    testframework::assert_command "grep -q '^clock=19 1$' '$prefix/out'" "$label rejects a restored position that overlaps another box"
}

test_bash_position_collision() {
    assert_position_collision "$(bs::shell::host)" "bash"
}

test_zsh_position_collision() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh position collision" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_position_collision "$zsh_bin" "zsh"
}

run_status_row_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=20; TERM_H=8; BOX_TYPES=(logo); LOGO_NAME=fedora
        dripfetch::detect_colour
        dripfetch::layout_boxes
        m=${BOX_META[logo]}; col=${m%% *}; row=${m#* }
        printf "%s\n%s\n%s %s\n" "$(( row + BOX_SLOT_H[logo] - 1 ))" "${RAIN_BLOCK_BOTTOM[1]}" "${RAIN_BLOCK_TOP[20]}" "${RAIN_BLOCK_BOTTOM[20]}"
        :
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_status_row() {
    local shell_bin="$1" label="$2" rc bottom block_bottom empty_top empty_bottom
    local prefix="${T}/${label}-status-row"
    rc="$(run_status_row_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label status-row probe runs"
    { IFS= read -r bottom; IFS= read -r block_bottom; IFS=' ' read -r empty_top empty_bottom; } < "${prefix}/out"
    testframework::assert_command "(( $bottom < 8 ))" "$label reserves the last terminal row for status"
    testframework::assert_equal "7" "$block_bottom" "$label keeps the box mask separate from the status row"
    testframework::assert_equal "9" "$empty_top" "$label leaves an empty column unblocked above the status row"
    testframework::assert_equal "0" "$empty_bottom" "$label leaves an empty column with no box mask"
}

test_bash_status_row() {
    assert_status_row "$(bs::shell::host)" "bash"
}

test_zsh_status_row() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh status row" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_status_row "$zsh_bin" "zsh"
}

run_zsh_time_fallback_probe() {
    local zsh_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$zsh_bin" -c '
        source <(sed "\$d" "$1")
        zmodload() { return 1; }
        date() { printf "13:05:00|Wed 25 Nov 2026|2026-11-25|November 2026|3"; }
        dripfetch::__time_parts
        printf "%s|%s|%s|%s|%s\n" "$NOW_STAMP" "$NOW_DATE" "$TODAY" "$MONTH_YEAR" "$FIRST_DOW"
        :
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

test_zsh_time_fallback() {
    local zsh_bin prefix="${T}/zsh-time-fallback" rc out
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh datetime fallback" "zsh is not installed / zsh не установлен"
        return 0
    fi
    rc="$(run_zsh_time_fallback_probe "$zsh_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "zsh datetime fallback runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "zsh datetime fallback has no diagnostics"
    out="$(<"${prefix}/out")"
    testframework::assert_equal '13:05:00|Wed 25 Nov 2026|2026-11-25|November 2026|3' "$out" "zsh falls back to date when zsh/datetime is unavailable"
}

run_calendar_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        CAL_START=monday
        dripfetch::__time_parts() { TODAY="2024-02-01"; FIRST_DOW=4; MONTH_YEAR="February 2024"; }
        dripfetch::calendar_lines | dripfetch::strip_ansi | sed "s/ *$//"
        printf -- "---\n"
        dripfetch::__time_parts() { TODAY="2023-02-01"; FIRST_DOW=3; MONTH_YEAR="February 2023"; }
        dripfetch::calendar_lines | dripfetch::strip_ansi | sed "s/ *$//"
        :
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_calendar_fixtures() {
    local shell_bin="$1" label="$2" rc out
    local prefix="${T}/${label}-calendar"
    rc="$(run_calendar_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label calendar probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label calendar probe has no diagnostics"
    out="$(<"${prefix}/out")"
    testframework::assert_equal $'February 2024\nMo Tu We Th Fr Sa Su\n          1  2  3  4\n 5  6  7  8  9 10 11\n12 13 14 15 16 17 18\n19 20 21 22 23 24 25\n26 27 28 29\n---\nFebruary 2023\nMo Tu We Th Fr Sa Su\n       1  2  3  4  5\n 6  7  8  9 10 11 12\n13 14 15 16 17 18 19\n20 21 22 23 24 25 26\n27 28' "$out" "$label aligns weekdays and handles leap years"
}

test_bash_calendar_fixtures() {
    assert_calendar_fixtures "$(bs::shell::host)" "bash"
}

test_zsh_calendar_fixtures() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh calendar fixtures" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_calendar_fixtures "$zsh_bin" "zsh"
}

test_bash_clock_12h() {
    assert_clock_12h "$(bs::shell::host)" "bash"
}

test_zsh_clock_12h() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh 12-hour clock" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_clock_12h "$zsh_bin" "zsh"
}

main() {
    print_header "Dripfetch State / Состояние dripfetch"
    testframework::init
    T="$(mktemp -d)"
    trap 'rm -rf "${T:?}"' EXIT
    mkdir -p "${T}/home" "${T}/config"

    testframework::section "Status row / Статусная строка"
    test_bash_status_row
    test_zsh_status_row

    testframework::section "Positions / Позиции"
    test_bash_positions_migration
    test_zsh_positions_migration
    test_bash_position_collision
    test_zsh_position_collision
    test_bash_move_clamp
    test_zsh_move_clamp
    test_bash_live_collision
    test_zsh_live_collision

    testframework::section "Hidden boxes / Скрытые боксы"
    test_bash_hidden_boxes
    test_zsh_hidden_boxes

    testframework::section "Clock / Часы"
    test_bash_clock_12h
    test_zsh_clock_12h
    test_zsh_time_fallback
    test_bash_calendar_fixtures
    test_zsh_calendar_fixtures

    testframework::summary
}

main "$@"
