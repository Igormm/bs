#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testdripfetchrenderunit.sh — responsive dripfetch layout and render regressions
# tests/unit/testdripfetchrenderunit.sh — адаптивная раскладка и рендер dripfetch

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

run_layout_probe() {
    local shell_bin="$1" width="$2" height="$3" prefix="$4" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        declare -A BOX_SLOT_W BOX_SLOT_H
        TERM_W=$2; TERM_H=$3
        BOX_TYPES=(logo sysinfo clock calendar text)
        LOGO_NAME=fedora
        dripfetch::detect_colour
        dripfetch::layout_boxes
        printf "clock-size|%s\n" "$CLOCK_SIZE"
        for t in "${BOX_TYPES[@]}"; do
            m=${BOX_META[$t]:-}
            col=${m%% *}; row=${m#* }
            printf "%s|%s|%s|%s|%s\n" "$t" "$row" "$col" "${BOX_SLOT_W[$t]:-0}" "${BOX_SLOT_H[$t]:-0}"
        done
        dripfetch::rain_draw() { :; }
        probe_prefix=$4
        : > "$probe_prefix/rendered"
        dripfetch::draw_box() { printf "render-%s|%s|%s\n" "$1" "$2" "$3" >> "$probe_prefix/rendered"; }
        dripfetch::render_frame >/dev/null
        cat "$4/rendered"
    ' _ "$DRIPFETCH_SCRIPT" "$width" "$height" "$prefix" > "${prefix}/layout" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_layout() {
    local shell_bin="$1" label="$2" width="$3" height="$4" expected_clock="$5"
    local prefix="${T}/${label}-${width}x${height}" rc type row col sw sh m
    local prev_type prev_row prev_col prev_sw prev_sh cur_type cur_row cur_col cur_sw cur_sh
    local -A seen=() expected=() rendered=()
    local -a rects=()
    rc="$(run_layout_probe "$shell_bin" "$width" "$height" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label ${width}x${height} layout probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label ${width}x${height} layout probe has no diagnostics"

    while IFS='|' read -r type row col sw sh; do
        if [[ "$type" == render-* ]]; then
            rendered[${type#render-}]=1
            testframework::assert_equal "${expected[${type#render-}]}" "$row|$col" "$label ${width}x${height} renderer uses ${type#render-} layout coordinates"
            continue
        fi
        if [[ "$type" == clock-size ]]; then
            testframework::assert_equal "$expected_clock" "$row" "$label ${width}x${height} uses the expected clock size"
            continue
        fi
        cur_type=$type; cur_row=$row; cur_col=$col; cur_sw=$sw; cur_sh=$sh
        seen[$cur_type]=1
        expected[$cur_type]="$row|$col"
        testframework::assert_command "(( row >= 1 && col >= 1 && sw > 0 && sh > 0 && row + sh - 1 <= $height && col + sw - 1 <= $width ))" "$label ${width}x${height} $type stays on screen"
        if (( ${#rects[@]} )); then
            for m in "${rects[@]}"; do
                # shellcheck disable=SC2034  # prev_* are interpolated into assert_command below
                IFS='|' read -r prev_type prev_row prev_col prev_sw prev_sh <<< "$m"
                testframework::assert_command "! (( $cur_row < $prev_row + $prev_sh && $cur_row + $cur_sh > $prev_row && $cur_col < $prev_col + $prev_sw && $cur_col + $cur_sw > $prev_col ))" "$label ${width}x${height} $cur_type does not overlap $prev_type"
            done
        fi
        rects+=("$cur_type|$cur_row|$cur_col|$cur_sw|$cur_sh")
    done < "${prefix}/layout"
    testframework::assert_equal "${#seen[@]}" "${#rendered[@]}" "$label ${width}x${height} renderer visits every laid-out box"
    testframework::assert_equal "5" "${#seen[@]}" "$label ${width}x${height} lays out every default box"
}

run_clip_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=20; TERM_H=8; PAD_H=0; PAD_V=0; BORDER_STYLE=none
        TEXT_CONTENT=abcdefghijklmnopqrstuvwxyz
        BOX_TITLE[text]=""
        dripfetch::set_colour border "#50FFC1"
        dripfetch::set_colour text "#D9E5F4"
        dripfetch::set_colour accent "#50FFC1"
        OUT=""
        dripfetch::draw_box text 1 1 10 4
        printf "%s" "$OUT" | dripfetch::strip_ansi
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_clipping() {
    local shell_bin="$1" label="$2" out rc
    local prefix="${T}/${label}-clip"
    rc="$(run_clip_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label clipping probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label clipping probe has no diagnostics"
    out="$(<"${prefix}/out")"
    testframework::assert_command "[[ '$out' == *abcdefgh* ]]" "$label keeps text that fits the slot"
    testframework::assert_command "[[ '$out' != *ijkl* ]]" "$label clips text at the slot boundary"
}

run_order_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=80; TERM_H=24; BG_SET=0; SEL_INDEX=-1
        BOX_TYPES=(logo); BOX_META[logo]="1 1"; BOX_VISIBLE[logo]=1
        dripfetch::rain_draw() { OUT+="RAIN"; }
        dripfetch::draw_box() { OUT+="BOX:$1"; }
        dripfetch::render_frame >/dev/null
        printf "%s" "$OUT"
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

run_hotpath_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=40; TERM_H=12; LOGO_NAME=fedora
        BOX_TYPES=(logo sysinfo clock calendar text)
        dripfetch::detect_colour
        dripfetch::set_colour border "#50FFC1"
        dripfetch::set_colour text "#D9E5F4"
        dripfetch::set_colour accent "#50FFC1"
        calls=$2/calls
        dates=$2/dates
        : > "$calls"; : > "$dates"
        sed() { printf "sed\n" >> "$calls"; command sed "$@"; }
        awk() { printf "awk\n" >> "$calls"; command awk "$@"; }
        date() { printf "date\n" >> "$dates"; command date "$@"; }
        dripfetch::clock_lines >/dev/null
        dripfetch::calendar_lines >/dev/null
        dripfetch::layout_boxes
        dripfetch::rain_init
        dripfetch::rain_respawn 0
        dripfetch::render_frame >/dev/null
        printf "%s %s\n" "$(wc -l < "$calls")" "$(wc -l < "$dates")"
    ' _ "$DRIPFETCH_SCRIPT" "$prefix" > "${prefix}/count" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_hotpath() {
    local shell_bin="$1" label="$2" rc external dates
    local prefix="${T}/${label}-hotpath"
    rc="$(run_hotpath_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label hot-path probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label hot-path probe has no diagnostics"
    IFS=' ' read -r external dates < "${prefix}/count"
    testframework::assert_equal "0" "$external" "$label renders without sed/awk subprocesses"
    testframework::assert_equal "0" "$dates" "$label formats clock and calendar without date subprocesses"
}

run_frame_budget_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=80; TERM_H=24; LOGO_NAME=fedora
        BOX_TYPES=(logo sysinfo clock calendar text)
        dripfetch::detect_colour
        dripfetch::set_colour border "#50FFC1"
        dripfetch::set_colour text "#D9E5F4"
        dripfetch::set_colour accent "#50FFC1"
        dripfetch::set_colour bg "#080B12"
        dripfetch::layout_boxes
        dripfetch::rain_init
        BG_SET=1; SEL_INDEX=-1
        start=$(date +%s%N)
        i=0
        while (( i < 20 )); do dripfetch::render_frame >/dev/null; i=$(( i + 1 )); done
        end=$(date +%s%N)
        printf "%s\n" "$(( (end - start) / 1000000 ))"
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_frame_budget() {
    local shell_bin="$1" label="$2" rc elapsed
    local prefix="${T}/${label}-frame-budget"
    rc="$(run_frame_budget_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label frame-budget probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label frame-budget probe has no diagnostics"
    elapsed="$(<"${prefix}/out")"
    testframework::assert_command "(( $elapsed < 2000 ))" "$label renders 20 frames in under two seconds"
}

test_bash_frame_budget() {
    assert_frame_budget "$(bs::shell::host)" "bash"
}

test_zsh_frame_budget() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh frame budget" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_frame_budget "$zsh_bin" "zsh"
}

run_rain_respawn_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=4; TERM_H=8; RAIN_INTENSITY=100
        dripfetch::rain_init
        x=0
        while (( x < RAIN_NCOL )); do RAIN_HEAD[$x]=-1; x=$(( x + 1 )); done
        dripfetch::rain_step
        x=0
        while (( x < RAIN_NCOL )); do printf "%s\n" "${RAIN_HEAD[$x]}"; x=$(( x + 1 )); done
        :
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_rain_respawn() {
    local shell_bin="$1" label="$2" rc head count=0
    local prefix="${T}/${label}-rain-respawn"
    rc="$(run_rain_respawn_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label rain-respawn probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label rain-respawn probe has no diagnostics"
    while IFS= read -r head; do
        count=$(( count + 1 ))
        testframework::assert_command "(( $head >= 0 && $head < 8 ))" "$label respawned drops re-enter the visible screen"
    done < "${prefix}/out"
    testframework::assert_equal "4" "$count" "$label emits one respawn position per column"
}

test_bash_rain_respawn() {
    assert_rain_respawn "$(bs::shell::host)" "bash"
}

test_zsh_rain_respawn() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh rain respawn" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_rain_respawn "$zsh_bin" "zsh"
}

run_incremental_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=40; TERM_H=12; LOGO_NAME=fedora; BOX_TYPES=(logo)
        dripfetch::detect_colour
        dripfetch::set_colour border "#50FFC1"
        dripfetch::set_colour text "#D9E5F4"
        dripfetch::set_colour accent "#50FFC1"
        dripfetch::set_colour bg "#080B12"
        dripfetch::layout_boxes
        dripfetch::rain_init
        BG_SET=1; SEL_INDEX=-1
        dripfetch::render_frame > "$2/first"
        dripfetch::rain_step
        dripfetch::render_frame > "$2/second"
        esc=$(printf "\033")
        first_clear=0; second_clear=0
        [[ "$(<"$2/first")" == *"${esc}[2J"* ]] && first_clear=1
        [[ "$(<"$2/second")" == *"${esc}[2J"* ]] && second_clear=1
        printf "%s %s %s %s\n" "$first_clear" "$second_clear" "$(wc -c < "$2/first")" "$(wc -c < "$2/second")"
    ' _ "$DRIPFETCH_SCRIPT" "$prefix" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_incremental_render() {
    local shell_bin="$1" label="$2" rc first_clear second_clear first_size second_size
    local prefix="${T}/${label}-incremental"
    rc="$(run_incremental_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label incremental probe runs"
    testframework::assert_command "[[ ! -s '$prefix/stderr' ]]" "$label incremental probe has no diagnostics"
    IFS=' ' read -r first_clear second_clear first_size second_size < "${prefix}/out"
    testframework::assert_equal "1" "$first_clear" "$label draws the first frame completely"
    testframework::assert_equal "0" "$second_clear" "$label does not clear the screen on later frames"
    testframework::assert_command "(( $second_size < $first_size ))" "$label emits less data on later frames"
}

test_bash_incremental_render() {
    assert_incremental_render "$(bs::shell::host)" "bash"
}

test_zsh_incremental_render() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh incremental render" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_incremental_render "$zsh_bin" "zsh"
}

run_rain_direction_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=1; TERM_H=8; RAIN_NCOL=1
        RAIN_HEAD[0]=5; RAIN_LEN[0]=3; RAIN_CHAR_X[0]="|"; RAIN_FG[0]=""
        RAIN_BLOCK_TOP[1]=9; RAIN_BLOCK_BOTTOM[1]=0
        OUT=""; dripfetch::rain_draw
        printf "%s" "$OUT"
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_rain_direction() {
    local shell_bin="$1" label="$2" rc out esc
    local prefix="${T}/${label}-rain-direction"
    rc="$(run_rain_direction_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label rain-direction probe runs"
    out="$(<"${prefix}/out")"; esc=$'\033'
    testframework::assert_command "[[ '$out' == *'${esc}[6;1H'* ]]" "$label positions the drop head absolutely"
    testframework::assert_command "[[ '$out' == *'${esc}[5;1H'* && '$out' == *'${esc}[4;1H'* ]]" "$label positions every tail cell absolutely"
    testframework::assert_command "[[ '$out' != *'${esc}[A'* && '$out' != *'${esc}[B'* ]]" "$label avoids relative cursor drift"
}

test_bash_rain_direction() {
    assert_rain_direction "$(bs::shell::host)" "bash"
}

test_zsh_rain_direction() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh rain direction" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_rain_direction "$zsh_bin" "zsh"
}

run_wrap_mode_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_ACTIVE=1; ORIG_STTY=""
        dripfetch::term_init
        dripfetch::term_restore
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_wrap_mode() {
    local shell_bin="$1" label="$2" rc out esc
    local prefix="${T}/${label}-wrap-mode"
    rc="$(run_wrap_mode_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label wrap-mode probe runs"
    out="$(<"${prefix}/out")"; esc=$'\033'
    testframework::assert_command "[[ '$out' == *'${esc}[?7l'* ]]" "$label disables terminal autowrap while drawing"
    testframework::assert_command "[[ '$out' == *'${esc}[?7h'* ]]" "$label restores terminal autowrap on exit"
}

test_bash_wrap_mode() {
    assert_wrap_mode "$(bs::shell::host)" "bash"
}

test_zsh_wrap_mode() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh wrap mode" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_wrap_mode "$zsh_bin" "zsh"
}

run_rain_erase_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=1; TERM_H=8; RAIN_NCOL=1
        RAIN_HEAD[0]=5; RAIN_LEN[0]=3; RAIN_OLD_HEAD[0]=4; RAIN_OLD_LEN[0]=3
        RAIN_CHAR_X[0]="|"; RAIN_FG[0]=""; RAIN_BLOCK_TOP[1]=9; RAIN_BLOCK_BOTTOM[1]=0
        OUT=""; dripfetch::rain_draw incremental
        printf "%s" "$OUT"
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_rain_erase() {
    local shell_bin="$1" label="$2" rc out esc
    local prefix="${T}/${label}-rain-erase"
    rc="$(run_rain_erase_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label rain-erase probe runs"
    out="$(<"${prefix}/out")"; esc=$'\033'
    testframework::assert_command "[[ '$out' == *'${esc}[3;1H '* ]]" "$label erases the old tail cell when a drop moves"
}

run_mask_move_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=40; TERM_H=12; BOX_TYPES=(logo); LOGO_NAME=fedora
        dripfetch::detect_colour
        dripfetch::layout_boxes
        dripfetch::sel_box
        dripfetch::move_sel 20 0
        printf "%s|%s|%s\n" "${BOX_META[logo]}" "${RAIN_BLOCK_TOP[21]}" "${RAIN_BLOCK_BOTTOM[21]}"
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_mask_move() {
    local shell_bin="$1" label="$2" rc meta top bottom
    local prefix="${T}/${label}-mask-move"
    rc="$(run_mask_move_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label mask-move probe runs"
    IFS='|' read -r meta top bottom < "${prefix}/out"
    testframework::assert_equal "21 1" "$meta" "$label moves the box"
    testframework::assert_equal "1" "$top" "$label rebuilds the rain mask at the new column"
    testframework::assert_equal "11" "$bottom" "$label rebuilds the rain mask height"
}

test_bash_rain_erase() {
    assert_rain_erase "$(bs::shell::host)" "bash"
}

test_zsh_rain_erase() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh rain erase" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_rain_erase "$zsh_bin" "zsh"
}

test_bash_mask_move() {
    assert_mask_move "$(bs::shell::host)" "bash"
}

test_zsh_mask_move() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh mask move" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_mask_move "$zsh_bin" "zsh"
}

run_status_rain_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=20; TERM_H=8; BOX_TYPES=(logo); LOGO_NAME=fedora
        dripfetch::detect_colour
        dripfetch::layout_boxes
        dripfetch::rain_init
        x=0
        while (( x < RAIN_NCOL )); do RAIN_HEAD[$x]=-1; x=$(( x + 1 )); done
        RAIN_HEAD[19]=7; RAIN_LEN[19]=1; RAIN_CHAR_X[19]="|"; RAIN_FG[19]=""
        RAIN_HEAD[18]=8; RAIN_LEN[18]=1; RAIN_CHAR_X[18]="|"; RAIN_FG[18]=""
        OUT=""; dripfetch::rain_draw incremental
        printf "%s" "$OUT"
    ' _ "$DRIPFETCH_SCRIPT" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_status_rain() {
    local shell_bin="$1" label="$2" rc out esc
    local prefix="${T}/${label}-status-rain"
    rc="$(run_status_rain_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label status-rain probe runs"
    out="$(<"${prefix}/out")"; esc=$'\033'
    testframework::assert_command "[[ '$out' != *'${esc}[8;20H'* ]]" "$label never draws rain on the status row"
    testframework::assert_command "[[ '$out' != *'${esc}[9;19H'* ]]" "$label never draws off-screen rain rows"
}

test_bash_status_rain() {
    assert_status_rain "$(bs::shell::host)" "bash"
}

test_zsh_status_rain() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh status rain" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_status_rain "$zsh_bin" "zsh"
}

run_weather_cache_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        TERM_W=80; TERM_H=24; BOX_TYPES=(weather)
        calls=$2/calls; : > "$calls"
        dripfetch::weather_lines() { printf "call\n" >> "$calls"; printf "sunny\n"; }
        dripfetch::layout_boxes
        dripfetch::__weather_refresh
        wc -l < "$calls"
    ' _ "$DRIPFETCH_SCRIPT" "$prefix" > "${prefix}/out" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

test_bash_weather_cache() {
    local prefix="${T}/bash-weather-cache" rc count
    rc="$(run_weather_cache_probe "$(bs::shell::host)" "$prefix")"
    testframework::assert_equal "0" "$rc" "bash weather-cache probe runs"
    count="$(<"${prefix}/out")"
    testframework::assert_equal "1" "$count" "bash reuses weather measured during layout"
}

test_bash_hotpath() {
    assert_hotpath "$(bs::shell::host)" "bash"
}

test_zsh_hotpath() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh hot path" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_hotpath "$zsh_bin" "zsh"
}

test_rain_behind_boxes() {
    local prefix="${T}/layer-order" out rc
    rc="$(run_order_probe "$(bs::shell::host)" "$prefix")"
    testframework::assert_equal "0" "$rc" "layer-order probe runs"
    out="$(<"${prefix}/out")"
    testframework::assert_command "[[ '$out' == *RAIN*BOX:logo* ]]" "rain is drawn before opaque boxes"
}

test_bash_clipping() {
    assert_clipping "$(bs::shell::host)" "bash"
}

test_zsh_clipping() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh clipping" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_clipping "$zsh_bin" "zsh"
}

test_bash_layout_80() {
    assert_layout "$(bs::shell::host)" "bash" 80 24 small
}

test_bash_layout_120() {
    assert_layout "$(bs::shell::host)" "bash" 120 40 big
}

test_zsh_layout_80() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh 80x24 layout" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_layout "$zsh_bin" "zsh" 80 24 small
}

test_zsh_layout_120() {
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh 120x40 layout" "zsh is not installed / zsh не установлен"
        return 0
    fi
    assert_layout "$zsh_bin" "zsh" 120 40 big
}

main() {
    print_header "Dripfetch Render / Рендер dripfetch"
    testframework::init
    T="$(mktemp -d)"
    trap 'rm -rf "${T:?}"' EXIT
    mkdir -p "${T}/home" "${T}/config"

    testframework::section "Frame budget / Бюджет кадра"
    test_bash_frame_budget
    test_zsh_frame_budget
    test_bash_rain_respawn
    test_zsh_rain_respawn
    test_bash_rain_direction
    test_zsh_rain_direction
    test_bash_wrap_mode
    test_zsh_wrap_mode
    test_bash_rain_erase
    test_zsh_rain_erase
    test_bash_mask_move
    test_zsh_mask_move
    test_bash_status_rain
    test_zsh_status_rain
    test_bash_weather_cache
    test_bash_incremental_render
    test_zsh_incremental_render

    testframework::section "Hot path / Горячий путь"
    test_bash_hotpath
    test_zsh_hotpath

    testframework::section "Layer order / Порядок слоёв"
    test_rain_behind_boxes

    testframework::section "Clipping / Обрезка"
    test_bash_clipping
    test_zsh_clipping

    testframework::section "Responsive layout / Адаптивная раскладка"
    test_bash_layout_80
    test_bash_layout_120
    test_zsh_layout_80
    test_zsh_layout_120

    testframework::summary
}

main "$@"
