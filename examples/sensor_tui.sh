#!/usr/bin/env bs
# shellcheck shell=bash
# examples/sensor_tui.sh — Touch sensor monitor TUI / TUI-монитор сенсорного устройства
#
# Реалтайм: координаты касания, состояние BTN_TOUCH, журнал событий,
# диагностика (d), смена устройства (↑/↓ или Tab), выход (q).
# Realtime: touch coordinates, BTN_TOUCH state, event log, diagnostics (d),
# device switching (up/down/Tab), quit (q).
#
# Попробуйте / Try it:
#   bs run examples/sensor_tui.sh
#   bs run examples/sensor_tui.sh --device event5

set -euo pipefail

load "core/args"
load "lib/io/streams"
load "lib/system/sensor"
load "lib/tui/tui"

declare -ga ST_DEVICES=()      # "eventN\tname"
declare -gi ST_SEL=0
declare -gA ST_VAL=()          # axis code -> current value
declare -gA ST_MIN=() ST_MAX=()
declare -ga ST_LOG=()
declare -g  ST_TOUCH=0
declare -g  ST_TRACK=0
declare -g  ST_DIRTY=1
declare -g  ST_DIAG=""
declare -gi ST_MODAL=0
declare -g  ST_ERR=""
declare -gi ST_ATTACHED=0

# ==========================================
# Сенсорный поток / sensor stream
# ==========================================

# @description Переподключить fd 9 на выбранное устройство / reconnect reader
st::attach() {
    # exec-редирект на закрытом FD фатален — закрываем только открытый
    # closing an unopened exec FD is fatal — close only when open
    (( ST_ATTACHED == 1 )) && exec 9<&-
    local -r ev="${ST_DEVICES[ST_SEL]%%$'\t'*}"
    ST_VAL=(); ST_MIN=(); ST_MAX=(); ST_LOG=(); ST_TOUCH=0; ST_TRACK=0
    ST_ERR=""
    if ! sensor::check "${ev}"; then
        ST_ERR="нет доступа к ${ev} (группа input?)"
        ST_ATTACHED=0
        return 0
    fi
    exec 9< <(sensor::events "${ev}")
    ST_ATTACHED=1
}

# @description Обработать одно событие / handle one event line
st::on_event() {
    local -r line="$1"
    local t c v
    read -r _ _ t c v <<< "${line}"
    local name
    name="$(sensor::code_name "${t}" "${c}")"
    case "${t}" in
        1) [[ "${c}" == 330 ]] && ST_TOUCH="${v}" ;;
        3)
            ST_VAL["${c}"]="${v}"
            [[ "${c}" == 63 ]] && { [[ "${v}" == -1 ]] && ST_TRACK=0 || ST_TRACK=1; }
            [[ -z "${ST_MIN[$c]:-}" || "${v}" -lt "${ST_MIN[$c]}" ]] && ST_MIN["${c}"]="${v}"
            [[ -z "${ST_MAX[$c]:-}" || "${v}" -gt "${ST_MAX[$c]}" ]] && ST_MAX["${c}"]="${v}"
            ;;
    esac
    ST_LOG+=("${name}=${v}")
    (( ${#ST_LOG[@]} > 12 )) && ST_LOG=("${ST_LOG[@]: -12}")
    ST_DIRTY=1
}

# @description Снять карту с fd 9 без блокировки / non-blocking drain
st::drain_sensor() {
    local line=""
    while IFS= read -r -t 0.05 -u 9 line 2>/dev/null; do
        is::not_empty "${line}" && st::on_event "${line}"
    done
    return 0
}

# ==========================================
# Клавиши через фоновый читатель / keys via background reader
# ==========================================

st::spawn_keys() {
    coproc ST_KEYS {
        local b b2 b3
        while IFS= read -r -s -n1 b; do
            case "${b}" in
                $'\e')
                    IFS= read -r -s -n1 -t 0.05 b2 || b2=""
                    if is::empty "${b2}"; then
                        printf 'K:ESC\n'
                    else
                        IFS= read -r -s -n1 -t 0.05 b3 || b3=""
                        case "${b2}${b3}" in
                            "[A") printf 'K:UP\n' ;;
                            "[B") printf 'K:DOWN\n' ;;
                            "[C") printf 'K:RIGHT\n' ;;
                            "[D") printf 'K:LEFT\n' ;;
                            *)    printf 'K:ESC\n' ;;
                        esac
                    fi ;;
                $'\n'|'') printf 'K:ENTER\n' ;;
                *)        printf 'K:%s\n' "${b}" ;;
            esac
        done
    }
}

# @description Неблокирующий опрос клавиш / non-blocking key poll
st::drain_keys() {
    local k=""
    while IFS= read -r -t 0.05 -u "${ST_KEYS[0]}" k 2>/dev/null; do
        k="${k#K:}"
        st::on_key "${k}"
    done
    return 0
}

st::on_key() {
    local -r key="$1"
    if (( ST_MODAL == 1 )); then
        ST_MODAL=0
        ST_DIRTY=1
        return
    fi
    case "${key}" in
        q|Q|й|Й|ESC) tui::quit; exit 0 ;;
        UP)   (( ST_SEL > 0 )) && { ST_SEL=$(( ST_SEL - 1 )); st::attach; ST_DIRTY=1; } ;;
        DOWN) (( ST_SEL < ${#ST_DEVICES[@]} - 1 )) && { ST_SEL=$(( ST_SEL + 1 )); st::attach; ST_DIRTY=1; } ;;
        TAB)  ST_SEL=$(( (ST_SEL + 1) % ${#ST_DEVICES[@]} )); st::attach; ST_DIRTY=1 ;;
        d|D|в|В)
            local ev="${ST_DEVICES[ST_SEL]%%$'\t'*}"
            ST_DIAG="$(utils::attempt sensor::diagnose "${ev}" 2)"
            ST_MODAL=1
            ST_DIRTY=1 ;;
    esac
}

# ==========================================
# Отрисовка / drawing
# ==========================================

st::draw() {
    local -r ev="${ST_DEVICES[ST_SEL]%%$'\t'*}"
    local -r name="${ST_DEVICES[ST_SEL]#*$'\t'}"
    local -i w=$(( TUI_COLS / 2 ))
    local head_st body_st warn_st
    head_st="$(tui::style bold cyan)"
    body_st="$(tui::style white)"
    warn_st="$(tui::style bold red)"

    tui::titlebar " BS Sensor Monitor — ${ev} (${name}) " "$(tui::style bold bg:blue white)"

    # панель устройств / device panel
    tui::box 2 1 "$(( w < 32 ? w : 32 ))" $(( TUI_LINES - 4 )) "устройства" "${head_st}"
    tui::list 3 2 "$(( (w < 32 ? w : 32) - 3 ))" $(( TUI_LINES - 7 )) ST_DEVICES "${ST_SEL}"
    tui::put $(( TUI_LINES - 4 )) 3 "↑↓ смена  d диагност" "$(tui::style dim)"
    tui::put $(( TUI_LINES - 3 )) 3 "q выход    Tab цикл" "$(tui::style dim)"

    # визуализация касания / touch visualization
    local -i vx=$(( (w < 32 ? w : 32) + 1 ))
    local -i vw=$(( TUI_COLS - vx - 2 ))
    tui::box 2 "${vx}" "${vw}" 10 "зона касания" "${head_st}"
    st::draw_pad "${vx}" "${vw}"

    # таблица осей / axis table
    tui::box 13 "${vx}" "${vw}" $(( TUI_LINES - 17 )) "оси (min..max)" "${head_st}"
    local -i r=14 c
    for c in "${!ST_VAL[@]}"; do
        (( r < TUI_LINES - 5 )) || break
        tui::put "${r}" $(( vx + 2 )) \
            "$(printf '%-22s %6s  [%d..%d]' "$(sensor::abs_name "${c}")" "${ST_VAL[$c]}" "${ST_MIN[$c]}" "${ST_MAX[$c]}")" "${body_st}"
        r=$(( r + 1 ))
    done

    # журнал / event log (последние 3)
    tui::put $(( TUI_LINES - 4 )) "${vx}" "log" "$(tui::style dim)"
    local -a last3=("${ST_LOG[@]: -3}")
    local -i i
    for (( i = 0; i < ${#last3[@]}; i++ )); do
        tui::put "$(( TUI_LINES - 3 + i ))" "${vx}" "${last3[$i]:0:$(( vw - 2 ))}" "$(tui::style gray)"
    done

    if is::not_empty "${ST_ERR}"; then
        tui::put $(( TUI_LINES - 3 )) "${vx}" "${ST_ERR}" "${warn_st}"
    fi

    local state="OK" state_st
    if is::not_empty "${ST_ERR}"; then
        state="NO ACCESS"
        state_st="$(tui::style bold red)"
    else
        state_st="$(tui::style bold green)"
    fi
    tui::statusbar " ${ev} • touch=${ST_TOUCH} track=${ST_TRACK} • ${state} " "${state_st}"

    (( ST_MODAL == 1 )) && st::draw_diag
    return 0
}

# @description Клетка-«пад» с курсором касания / touch pad cell with cursor
st::draw_pad() {
    local -r bx="$1" bw="$2"
    local -i ph=6 pw=$(( bw - 2 ))
    local -i x=0 y=0
    # масштаб по наблюдаемому диапазону (или 4096 по умолчанию для ёмкостных)
    # scale by observed range (or 4096 default for capacitive)
    local -i xmax="${ST_MAX[0]:-4095}" xmin="${ST_MIN[0]:-0}"
    local -i ymax="${ST_MAX[1]:-4095}" ymin="${ST_MIN[1]:-0}"
    (( xmax > xmin )) || xmax=$(( xmin + 1 ))
    (( ymax > ymin )) || ymax=$(( ymin + 1 ))
    x=$(( ( ${ST_VAL[0]:-0} - xmin ) * (pw - 1) / (xmax - xmin) ))
    y=$(( ( ${ST_VAL[1]:-0} - ymin ) * (ph - 1) / (ymax - ymin) ))
    (( x >= 0 && x < pw )) || x=0
    (( y >= 0 && y < ph )) || y=0
    local -i r c
    local marker
    if [[ "${ST_TOUCH}" == 1 ]]; then marker="●"; else marker="○"; fi
    local pad_st
    if [[ "${ST_TOUCH}" == 1 ]]; then
        pad_st="$(tui::style green)"
    else
        pad_st="$(tui::style gray)"
    fi
    for (( r = 0; r < ph; r++ )); do
        local row=""
        for (( c = 0; c < pw; c++ )); do
            if [[ "${r}" == "${y}" && "${c}" == "${x}" ]]; then
                row+="${marker}"
            else
                row+="·"
            fi
        done
        tui::put "$(( 3 + r ))" "$(( bx + 1 ))" "${row}" "${pad_st}"
    done
}

# @description Модалка диагностики / diagnostics modal
st::draw_diag() {
    local -i w=$(( TUI_COLS - 6 )) h=$(( TUI_LINES - 4 ))
    (( w > 80 )) && w=80
    (( h > 18 )) && h=18
    local -i bx=$(( (TUI_COLS - w) / 2 )) by=$(( (TUI_LINES - h) / 2 ))
    tui::box "${by}" "${bx}" "${w}" "${h}" "диагностика (люб. клавиша — закрыть)" "$(tui::style bold yellow)"
    local -i r=$(( by + 2 )) line
    while IFS= read -r line; do
        (( r < by + h - 1 )) || break
        local st=""
        str::contains "${line}" "[FAIL]" && st="$(tui::style red)"
        str::contains "${line}" "[WARN]" && st="$(tui::style yellow)"
        str::contains "${line}" "[PASS]" && st="$(tui::style green)"
        tui::put "${r}" "$(( bx + 2 ))" "${line:0:$(( w - 4 ))}" "${st}"
        r=$(( r + 1 ))
    done <<< "${ST_DIAG}"
}

# ==========================================
# Main loop
# ==========================================

main() {
    args::flag device value
    args::flag_describe device "Start with this event device (eventN)"
    args::require "$@"

    local want=""
    args::flag_is_set device && want="$(args::flag_get device)"

    mapfile -t ST_DEVICES < <(sensor::devices)
    if (( ${#ST_DEVICES[@]} == 0 )); then
        io::streams::eprint "Сенсорные устройства не найдены / no input devices"
        exit "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    if is::not_empty "${want}"; then
        local -i i
        for (( i = 0; i < ${#ST_DEVICES[@]}; i++ )); do
            [[ "${ST_DEVICES[i]%%$'\t'*}" == "${want}" ]] && ST_SEL="${i}"
        done
    fi

    tui::init
    tui::mouse_off
    st::attach
    st::spawn_keys

    while true; do
        tui::handle_resize
        st::drain_sensor
        st::drain_keys
        if (( ST_DIRTY == 1 )); then
            ST_DIRTY=0
            tui::buf::clear
            st::draw
            tui::render
        fi
    done

    tui::quit
}

main "$@"
