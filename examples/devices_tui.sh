#!/usr/bin/env bs
# shellcheck shell=bash
# examples/devices_tui.sh — TUI configurator for input devices
# examples/devices_tui.sh — TUI-конфигуратор устройств ввода
#
# Полноэкранный TUI (lib/tui/tui): список устройств с текущими параметрами,
# экран параметров устройства с живым применением, экран обзора и сохранения в
# BS-профиль. Устройства скрыты за единым контрактом драйверов (lib/system/devicectl):
# добавить драйвер = зарегистрировать его, сам TUI не меняется.
# A full-screen TUI (lib/tui/tui): device list with current parameters, a per-device
# parameter screen with live apply, and a review/profile screen. Devices are hidden
# behind the uniform driver contract (lib/system/devicectl): adding a driver means
# registering it, the TUI itself is unchanged.
#
# Клавиши / Keys:
#   ↑↓ j k     выбор / select
#   ←→ Tab     экраны / screens
#   Enter      открыть/править / open/edit
#   o          ввести вручную / enter manually
#   r          перечитать устройства / re-detect
#   s          сохранить профиль (обзор) / save profile (review)
#   a          применить профиль (обзор) / apply profile (review)
#   q          выход / quit

load "lib/tui/tui"
load "lib/system/devicectl"
load "lib/system/devprofile"

# Data / Данные

declare -ga DEVICES=()   # driver<TAB>handle<TAB>label<TAB>kind
declare -g  DEV_DRIVER="" DEV_HANDLE="" DEV_LABEL=""
declare -ga PARAMS=()    # param<TAB>type<TAB>current<TAB>default<TAB>choices<TAB>tip
declare -gi SCR=0        # 0 list, 1 params, 2 review
declare -gi SEL=0 PSEL=0
declare -g  STATUS=""
declare -g  ACTIVE_PROFILE=""

# Modal state / Состояние модалок
declare -g  MODAL="" MO_TARGET="" MO_VALUE="" MO_CURSOR=0
declare -ga MO_VALS=()
declare -gi MO_SEL=0

# Editing params / Правка параметров
declare -g  EDIT_PARAM="" EDIT_TYPE="" EDIT_DEFAULT=""

# Helpers / Помощники

dtui::selected() {
    DEV_DRIVER=""; DEV_HANDLE=""; DEV_LABEL=""
    (( ${#DEVICES[@]} > 0 )) || return 1
    local -r line="${DEVICES[${SEL}]}"
    IFS=$'\t' read -r DEV_DRIVER DEV_HANDLE DEV_LABEL _ <<< "${line}"
    return 0
}

dtui::load_params() {
    PARAMS=()
    dtui::selected || return 1
    local line
    while IFS=$'\t' read -r line; do
        [[ -n "${line}" ]] && PARAMS+=("${line}")
    done < <(device::params "${DEV_DRIVER}" "${DEV_HANDLE}")
    return 0
}

dtui::reload() {
    DEVICES=()
    local line
    while IFS= read -r line; do
        [[ -n "${line}" ]] && DEVICES+=("${line}")
    done < <(device::list 2>/dev/null)
    (( ${#DEVICES[@]} > 0 )) || DEVICES=()
    (( SEL < ${#DEVICES[@]} )) || SEL=0
}

dtui::collect() {
    local line drv handle
    for line in "${DEVICES[@]}"; do
        IFS=$'\t' read -r drv handle _ _ <<< "${line}"
        [[ -n "${drv}" && -n "${handle}" ]] || continue
        local snap
        while IFS= read -r snap; do
            [[ -z "${snap}" ]] && continue
            printf '%s\t%s\t%s\n' "${drv}" "${handle}" "${snap}"
        done < <(device::snapshot "${drv}" "${handle}" 2>/dev/null)
    done
}

dtui::apply_edit() {
    local -r v="$1"
    if device::set "${DEV_DRIVER}" "${DEV_HANDLE}" "${EDIT_PARAM}" "${v}"; then
        STATUS="OK: ${EDIT_PARAM}=${v}"
    else
        STATUS="деградация / degraded: ${EDIT_PARAM} для ${DEV_LABEL}"
    fi
}

# Draw / Отрисовка

dtui::draw_sidebar() {
    local -i i
    local -a steps=("Devices" "Params" "Review")
    tui::box 2 1 20 6 "Steps" "$(tui::style bold magenta)"
    for (( i = 0; i < 3; i++ )); do
        if (( i == SCR )); then
            tui::put $(( 3 + i )) 3 "▸ ${steps[${i}]}" "$(tui::style bold reverse white)"
        else
            tui::put $(( 3 + i )) 3 "  ${steps[${i}]}" ""
        fi
    done
}

dtui::draw_list() {
    local -i i
    tui::box 2 23 $((TUI_COLS - 24)) $(( TUI_LINES - 4 )) "Devices" "$(tui::style bold cyan)"
    if (( ${#DEVICES[@]} == 0 )); then
        tui::put 4 25 "ничего не найдено / nothing found (r — re-detect)" "$(tui::style dim)"
        return 0
    fi
    local -i total=${#DEVICES[@]} vis=$(( TUI_LINES - 6 )) offset=0 idx
    (( SEL < offset )) && offset="${SEL}"
    (( SEL >= offset + vis )) && offset=$(( SEL - vis + 1 ))
    for (( i = 0; i < vis; i++ )); do
        idx=$(( offset + i ))
        (( idx >= total )) && break
        local line="${DEVICES[${idx}]}" drv handle label kind
        IFS=$'\t' read -r drv handle label kind <<< "${line}"
        if (( idx == SEL )); then
            tui::put $(( 3 + i )) 25 "▸ ${label}  [${kind}]" "$(tui::style bold reverse cyan)"
        else
            tui::put $(( 3 + i )) 25 "  ${label}  [${kind}]" ""
        fi
    done
}

dtui::draw_params() {
    local -i i
    tui::box 2 23 $((TUI_COLS - 24)) $(( TUI_LINES - 4 )) "${DEV_LABEL}" "$(tui::style bold cyan)"
    tui::put 3 25 "driver: ${DEV_DRIVER}" "$(tui::style dim)"
    if (( ${#PARAMS[@]} == 0 )); then
        tui::put 5 25 "нет параметров / no parameters" "$(tui::style dim)"
        return 0
    fi
    local -i total=${#PARAMS[@]} vis=$(( TUI_LINES - 8 )) offset=0 idx
    (( PSEL < offset )) && offset="${PSEL}"
    (( PSEL >= offset + vis )) && offset=$(( PSEL - vis + 1 ))
    for (( i = 0; i < vis; i++ )); do
        idx=$(( offset + i ))
        (( idx >= total )) && break
        local name cur type
        name="$(printf '%s' "${PARAMS[${idx}]}" | awk -F'\t' '{print $1}')"
        cur="$(printf '%s' "${PARAMS[${idx}]}" | awk -F'\t' '{print $3}')"
        type="$(printf '%s' "${PARAMS[${idx}]}" | awk -F'\t' '{print $2}')"
        if (( idx == PSEL )); then
            tui::put $(( 4 + i )) 25 "▸ ${name} = ${cur}  (${type})" "$(tui::style bold reverse cyan)"
        else
            tui::put $(( 4 + i )) 25 "  ${name} = ${cur}  (${type})" ""
        fi
    done
}

dtui::draw_review() {
    local -i i row=4
    tui::box 2 23 $((TUI_COLS - 24)) $(( TUI_LINES - 4 )) "Review & profile" "$(tui::style bold green)"
    tui::put 3 25 "Профиль / profile: ${ACTIVE_PROFILE:-нет / none}" "$(tui::style dim)"
    local line drv handle label
    for line in "${DEVICES[@]}"; do
        IFS=$'\t' read -r drv handle label _ <<< "${line}"
        local snap
        while IFS= read -r snap; do
            (( row < TUI_LINES - 2 )) || break 2
            [[ -z "${snap}" ]] && continue
            tui::put "${row}" 25 "  ${label:0:20}: ${snap}" "$(tui::style bold)"
            row=$(( row + 1 ))
        done < <(device::snapshot "${drv}" "${handle}" 2>/dev/null)
    done
    tui::put $(( TUI_LINES - 3 )) 25 "s сохранить / save · a применить / apply" "$(tui::style dim)"
}

dtui::draw_frame() {
    tui::titlebar "  BS Devices • ${TUI_COLS}x${TUI_LINES}" "$(tui::style bold bg_blue white)"
    dtui::draw_sidebar
    case "${SCR}" in
        0) dtui::draw_list ;;
        1) dtui::draw_params ;;
        2) dtui::draw_review ;;
    esac
    tui::statusbar "  ${STATUS:-←→ screens  ↑↓ select  Enter open  o input  q quit}" "$(tui::style bg_black white)"
}

dtui::draw_input() {
    local -i w=56 h=5
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    tui::box "${by}" "${bx}" "${w}" "${h}" "${MO_TARGET}" "$(tui::style bold cyan)"
    tui::input $(( by + 2 )) $(( bx + 3 )) $(( w - 5 )) "${MO_VALUE}" "${MO_CURSOR}"
}

dtui::draw_picker() {
    local -i w=40 h=$(( ${#MO_VALS[@]} + 2 ))
    (( h > TUI_LINES - 4 )) && h=$(( TUI_LINES - 4 ))
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}" i
    tui::box "${by}" "${bx}" "${w}" "${h}" "${EDIT_PARAM}" "$(tui::style bold cyan)"
    for (( i = 0; i < ${#MO_VALS[@]} && i < h - 2; i++ )); do
        if (( i == MO_SEL )); then
            tui::put $(( by + 1 + i )) $(( bx + 2 )) "▸ ${MO_VALS[${i}]}" "$(tui::style bold reverse)"
        else
            tui::put $(( by + 1 + i )) $(( bx + 2 )) "  ${MO_VALS[${i}]}" ""
        fi
    done
}

# Actions / Действия

dtui::open_input() {
    MODAL="input"; MO_TARGET="$1"; MO_VALUE="$2"; MO_CURSOR="${#MO_VALUE}"
}

dtui::open_picker() {
    MODAL="picker"
    MO_VALS=()
    local -r choices="$(printf '%s' "${PARAMS[${PSEL}]}" | awk -F'\t' '{print $5}')"
    local IFS0="${IFS}"; IFS=','
    read -r -a MO_VALS <<< "${choices}"
    IFS="${IFS0}"
    MO_SEL=0
}

dtui::start_edit() {
    EDIT_PARAM="$(printf '%s' "${PARAMS[${PSEL}]}" | awk -F'\t' '{print $1}')"
    EDIT_TYPE="$(printf '%s' "${PARAMS[${PSEL}]}" | awk -F'\t' '{print $2}')"
    EDIT_DEFAULT="$(printf '%s' "${PARAMS[${PSEL}]}" | awk -F'\t' '{print $4}')"
    case "${EDIT_TYPE}" in
        bool)
            local -r cur="$(printf '%s' "${PARAMS[${PSEL}]}" | awk -F'\t' '{print $3}')"
            local nv="1"; [[ "${cur}" == "1" || "${cur}" == "true" || "${cur}" == "on" ]] && nv="0"
            dtui::apply_edit "${nv}"
            dtui::load_params
            ;;
        enum:*) dtui::open_picker ;;
        *) dtui::open_input "${EDIT_PARAM}" "${EDIT_DEFAULT}" ;;
    esac
}

dtui::save_profile() {
    dtui::open_input "profile save" "${ACTIVE_PROFILE}"
}

dtui::apply_profile() {
    dtui::open_input "profile apply" "${ACTIVE_PROFILE}"
}

# Key dispatch / Диспетчер клавиш
#
# Обрабатывает одну клавишу (модалки, экраны, действия) и сигнализирует о
# выходе кодом 1. Вынесено из цикла main, чтобы логику можно было тестировать
# напрямую, как tui::app::key в lib/tui/app.
# Handles one key (modals, screens, actions) and signals quit with status 1.
# Extracted from the main loop so the logic is directly testable, mirroring
# tui::app::key in lib/tui/app.
# @param $1 key name (as produced by tui::key_read) / имя клавиши
# @return 0 continue, 1 quit / 0 продолжить, 1 выход
dtui::key() {
    TUI_KEY="${1:-}"
    if [[ -n "${MODAL}" ]]; then
        case "${MODAL}" in
            input)
                case "${TUI_KEY}" in
                    ENTER) MODAL=""
                           case "${MO_TARGET}" in
                               "profile save")  devprofile::save "${MO_VALUE}" < <(dtui::collect) && { STATUS="сохранён профиль / profile saved: ${MO_VALUE}"; ACTIVE_PROFILE="${MO_VALUE}"; } ;;
                               "profile apply") devprofile::apply "${MO_VALUE}" && STATUS="применён профиль / profile applied: ${MO_VALUE}" ;;
                               *) dtui::apply_edit "${MO_VALUE}"; dtui::load_params ;;
                           esac ;;
                    ESC) MODAL="" ;;
                    BACKSPACE)
                        if (( MO_CURSOR > 0 )); then
                            MO_VALUE="${MO_VALUE:0:${MO_CURSOR}-1}${MO_VALUE:${MO_CURSOR}}"
                            MO_CURSOR=$(( MO_CURSOR - 1 ))
                        else
                            # Прежняя вставка `(( ... )) || break` выходила из всего цикла
                            # The old inline `(( ... )) || break` exited the whole loop
                            return 1
                        fi ;;
                    LEFT)  (( MO_CURSOR > 0 )) && MO_CURSOR=$(( MO_CURSOR - 1 )) ;;
                    RIGHT) (( MO_CURSOR < ${#MO_VALUE} )) && MO_CURSOR=$(( MO_CURSOR + 1 )) ;;
                    *) MO_VALUE="${MO_VALUE:0:${MO_CURSOR}}${TUI_KEY}${MO_VALUE:${MO_CURSOR}}"
                       MO_CURSOR=$(( MO_CURSOR + 1 )) ;;
                esac
                ;;
            picker)
                case "${TUI_KEY}" in
                    ENTER) MODAL=""; dtui::apply_edit "${MO_VALS[${MO_SEL}]}"; dtui::load_params ;;
                    ESC) MODAL="" ;;
                    UP|k|K) (( MO_SEL > 0 )) && MO_SEL=$(( MO_SEL - 1 )) ;;
                    DOWN|j|J) (( MO_SEL < ${#MO_VALS[@]} - 1 )) && MO_SEL=$(( MO_SEL + 1 )) ;;
                esac
                ;;
        esac
        return 0
    fi

    case "${SCR}" in
        0)
            case "${TUI_KEY}" in
                q|Q|й|Й) return 1 ;;
                r|R) dtui::reload; STATUS="перечитано / re-detected" ;;
                UP|k|K) (( SEL > 0 )) && SEL=$(( SEL - 1 )) ;;
                DOWN|j|J) (( SEL < ${#DEVICES[@]} - 1 )) && SEL=$(( SEL + 1 )) ;;
                ENTER|RIGHT|TAB)
                    if dtui::selected; then
                        SCR=1; PSEL=0; dtui::load_params
                    fi ;;
            esac
            ;;
        1)
            case "${TUI_KEY}" in
                q|Q|й|Й) return 1 ;;
                LEFT|TAB) SCR=0 ;;
                o|O) dtui::open_input "${EDIT_PARAM:-param}" "${EDIT_DEFAULT:-}" ;;
                ENTER) dtui::start_edit ;;
                UP|k|K) (( PSEL > 0 )) && PSEL=$(( PSEL - 1 )) ;;
                DOWN|j|J) (( PSEL < ${#PARAMS[@]} - 1 )) && PSEL=$(( PSEL + 1 )) ;;
                RIGHT) SCR=2 ;;
            esac
            ;;
        2)
            case "${TUI_KEY}" in
                q|Q|й|Й) return 1 ;;
                LEFT|TAB) SCR=1 ;;
                s|S) dtui::save_profile ;;
                a|A) dtui::apply_profile ;;
            esac
            ;;
    esac
    return 0
}

# Main loop / Главный цикл

main() {
    tui::init
    dtui::reload
    ACTIVE_PROFILE="$(devprofile::active)"

    while true; do
        tui::handle_resize
        tui::buf::clear
        dtui::draw_frame
        [[ "${MODAL}" == "input" ]] && dtui::draw_input
        [[ "${MODAL}" == "picker" ]] && dtui::draw_picker
        tui::render
        tui::key_read
        dtui::key "${TUI_KEY}" || break
    done

    tui::quit
}

if bs::is_main; then
    main "$@"
fi
