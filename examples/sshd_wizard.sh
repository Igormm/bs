#!/usr/bin/env bs
# shellcheck shell=bash
# examples/sshd_wizard.sh — interactive TUI for building an sshd config
# examples/sshd_wizard.sh — интерактивный TUI для сборки конфига sshd
#
# Full-screen wizard on lib/tui/tui. Left: sections. Center: parameters of the
# selected section with their values. Bottom: a two-line Russian tip for the
# selected parameter. Modals edit values. P — profile; V — preview; A — apply.
# Полноэкранный визард на lib/tui/tui. Слева — секции. По центру — параметры
# секции со значениями. Внизу — двухстрочная русская подсказка выбранного
# параметра. Модалки редактируют значения. P — профиль, V — предпросмотр,
# A — применить.
#
# Run / Запуск:
#   bs run examples/sshd_wizard.sh
#   ./examples/sshd_wizard.sh [--dry-run] [--help]
#
# Keys / Клавиши:
#   ←→ секция · ↑↓ параметр · Enter правка · Space toggle · P профиль ·
#   V preview · A apply · r сброс · ? справка · q выход

load "lib/system/sshd"
load "lib/tui/tui"

# ==========================================
# State / Состояние
# ==========================================

# @global SSHD_WZ_SECTIONS — Sshd wizard: section names (category: state)
# @global SSHD_WZ_SECTIONS — Визард sshd: имена секций (категория: state)
declare -ga SSHD_WZ_SECTIONS=()
# @global SSHD_WZ_NAMES — Sshd wizard: params of current section (category: state)
# @global SSHD_WZ_NAMES — Визард sshd: параметры текущей секции (категория: state)
declare -ga SSHD_WZ_NAMES=()
# @global SSHD_WZ_VALUES — Sshd wizard: chosen param=value (category: state)
# @global SSHD_WZ_VALUES — Визард sshd: выбранные param=value (категория: state)
declare -gA SSHD_WZ_VALUES=()
# @global SSHD_WZ_SECTION — Sshd wizard: selected section index (category: state)
# @global SSHD_WZ_SECTION — Визард sshd: индекс выбранной секции (категория: state)
declare -gi SSHD_WZ_SECTION=0
# @global SSHD_WZ_SELECT — Sshd wizard: selected param index (category: state)
# @global SSHD_WZ_SELECT — Визард sshd: индекс выбранного параметра (категория: state)
declare -gi SSHD_WZ_SELECT=0
# @global SSHD_WZ_PROFILE — Sshd wizard: chosen profile (category: state)
# @global SSHD_WZ_PROFILE — Визард sshd: выбранный профиль (категория: state)
declare -g SSHD_WZ_PROFILE="custom"
# @global SSHD_WZ_TARGET — Sshd wizard: apply target dropin|main|print (category: state)
# @global SSHD_WZ_TARGET — Визард sshd: цель dropin|main|print (категория: state)
declare -g SSHD_WZ_TARGET="dropin"
# @global SSHD_WZ_VIEW — Sshd wizard: active view (category: state)
# @global SSHD_WZ_VIEW — Визард sshd: активный экран (категория: state)
declare -g SSHD_WZ_VIEW="params"
# @global SSHD_WZ_STATUS — Sshd wizard: status message (category: state)
# @global SSHD_WZ_STATUS — Визард sshd: сообщение статуса (категория: state)
declare -g SSHD_WZ_STATUS=""
# @global TUI_LINES_MINUS — Sshd wizard: section box height (category: state)
# @global TUI_LINES_MINUS — Визард sshd: высота рамки секций (категория: state)
declare -gi TUI_LINES_MINUS=20
# @global SSHD_WZ_EDIT_VALUE — Sshd wizard: input modal buffer (category: state)
# @global SSHD_WZ_EDIT_VALUE — Визард sshd: буфер ввода модалки (категория: state)
declare -g SSHD_WZ_EDIT_VALUE=""
# @global SSHD_WZ_EDIT_CURSOR — Sshd wizard: input modal cursor (category: state)
# @global SSHD_WZ_EDIT_CURSOR — Визард sshd: курсор ввода модалки (категория: state)
declare -gi SSHD_WZ_EDIT_CURSOR=0
# @global SSHD_WZ_EDIT_OPTIONS — Sshd wizard: choice options (category: state)
# @global SSHD_WZ_EDIT_OPTIONS — Визард sshd: варианты выбора (категория: state)
declare -ga SSHD_WZ_EDIT_OPTIONS=()
# @global SSHD_WZ_EDIT_SEL — Sshd wizard: choice selection (category: state)
# @global SSHD_WZ_EDIT_SEL — Визард sshd: выбранный вариант (категория: state)
declare -gi SSHD_WZ_EDIT_SEL=0
# @global SSHD_WZ_EDIT_ERR — Sshd wizard: validation error (category: state)
# @global SSHD_WZ_EDIT_ERR — Визард sshd: ошибка валидации (категория: state)
declare -g SSHD_WZ_EDIT_ERR=""
# @global SSHD_WZ_EDIT_MODE — Sshd wizard: input|choice (category: state)
# @global SSHD_WZ_EDIT_MODE — Визард sshd: input|choice (категория: state)
declare -g SSHD_WZ_EDIT_MODE=""

# @private Fill SSHD_WZ_SECTIONS from the catalog / Заполнить секции из каталога
sshd_wz::load_sections() {
    SSHD_WZ_SECTIONS=()
    local name section
    for name in "${SSHD_PARAM_ORDER[@]}"; do
        section="${SSHD_PARAMS[$name]%%|*}"
        arr::contains SSHD_WZ_SECTIONS "${section}" || SSHD_WZ_SECTIONS+=("${section}")
    done
}

# @private Fill SSHD_WZ_NAMES with the parameters of the current section
sshd_wz::load_names() {
    SSHD_WZ_NAMES=()
    local -r section="${SSHD_WZ_SECTIONS[$SSHD_WZ_SECTION]:-}"
    local name
    for name in "${SSHD_PARAM_ORDER[@]}"; do
        [[ "${SSHD_PARAMS[$name]%%|*}" == "${section}" ]] && SSHD_WZ_NAMES+=("${name}")
    done
    if (( SSHD_WZ_SELECT >= ${#SSHD_WZ_NAMES[@]} )); then
        SSHD_WZ_SELECT=0
    fi
    return 0
}

# @private Apply a profile into SSHD_WZ_VALUES / Применить профиль в значения
# @param $1 basic|strict|paranoid|custom
sshd_wz::apply_profile() {
    local -r profile="${1:?profile required}"
    SSHD_WZ_PROFILE="${profile}"
    [[ "${profile}" == "custom" ]] && return 0
    local line key val
    while IFS= read -r line; do
        is::empty "${line}" && continue
        key="${line%%=*}"; val="${line#*=}"
        SSHD_WZ_VALUES["${key}"]="${val}"
    done < <(sshd::profile "${profile}")
    return 0
}

# @private Open the right editor for the selected parameter
sshd_wz::begin_edit() {
    local -r name="${SSHD_WZ_NAMES[$SSHD_WZ_SELECT]:-}"
    is::empty "${name}" && return 0
    SSHD_WZ_EDIT_ERR=""
    SSHD_WZ_EDIT_SEL=0
    local -r type="$(sshd::param_type "${name}")"
    local current="${SSHD_WZ_VALUES[$name]:-$(sshd::param_default "${name}")}"
    case "${type}" in
        bool) SSHD_WZ_EDIT_OPTIONS=("yes" "no") ;;
        enum:*)
            local IFS=','
            read -ra SSHD_WZ_EDIT_OPTIONS <<< "${type#enum:}"
            ;;
        *) SSHD_WZ_EDIT_OPTIONS=() ;;
    esac
    if (( ${#SSHD_WZ_EDIT_OPTIONS[@]} > 0 )); then
        SSHD_WZ_EDIT_MODE="choice"
        local i
        for i in "${!SSHD_WZ_EDIT_OPTIONS[@]}"; do
            [[ "${SSHD_WZ_EDIT_OPTIONS[$i]}" == "${current}" ]] && SSHD_WZ_EDIT_SEL=$i
        done
    else
        SSHD_WZ_EDIT_MODE="input"
        SSHD_WZ_EDIT_VALUE="${current}"
        SSHD_WZ_EDIT_CURSOR=${#current}
    fi
    tui::modal::open edit sshd_wz::modal_edit_draw
    return 0
}

# @private Validate and commit the editor value
sshd_wz::commit_edit() {
    local -r name="${SSHD_WZ_NAMES[$SSHD_WZ_SELECT]:-}"
    local value="${SSHD_WZ_EDIT_VALUE}"
    (( ${#SSHD_WZ_EDIT_OPTIONS[@]} > 0 )) && value="${SSHD_WZ_EDIT_OPTIONS[$SSHD_WZ_EDIT_SEL]}"
    if sshd::validate "${name}" "${value}"; then
        SSHD_WZ_VALUES["${name}"]="${value}"
        SSHD_WZ_EDIT_ERR=""
        tui::modal::close
    else
        SSHD_WZ_EDIT_ERR="Недопустимое значение / invalid value: ${value}"
    fi
    return 0
}

sshd_wz::modal_edit_draw() {
    local -i w=64 h=8
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local -r name="${SSHD_WZ_NAMES[$SSHD_WZ_SELECT]:-}"
    tui::box "${by}" "${bx}" "${w}" "${h}" "Правка / Edit: ${name}" "$(tui::style bold cyan)"
    if [[ "${SSHD_WZ_EDIT_MODE}" == "choice" ]]; then
        local i
        for i in "${!SSHD_WZ_EDIT_OPTIONS[@]}"; do
            if (( i == SSHD_WZ_EDIT_SEL )); then
                tui::put $(( by + 1 + i )) $(( bx + 2 )) "▸ ${SSHD_WZ_EDIT_OPTIONS[$i]}" "$(tui::style bold reverse cyan)"
            else
                tui::put $(( by + 1 + i )) $(( bx + 2 )) "  ${SSHD_WZ_EDIT_OPTIONS[$i]}" ""
            fi
        done
    else
        tui::put $(( by + 2 )) $(( bx + 2 )) "Значение / Value:" ""
        tui::input $(( by + 3 )) $(( bx + 2 )) $(( w - 4 )) "${SSHD_WZ_EDIT_VALUE}" "${SSHD_WZ_EDIT_CURSOR}"
    fi
    is::not_empty "${SSHD_WZ_EDIT_ERR}" && tui::put $(( by + h - 2 )) $(( bx + 2 )) "${SSHD_WZ_EDIT_ERR}" "$(tui::style bold red)"
    tui::put $(( by + h - 1 )) $(( bx + 2 )) "Enter — OK · Esc — отмена" "$(tui::style dim)"
}

sshd_wz::handle_edit_key() {
    if [[ "${SSHD_WZ_EDIT_MODE}" == "choice" ]]; then
        case "${TUI_KEY}" in
            UP|k|K|о|О)   (( SSHD_WZ_EDIT_SEL > 0 )) && SSHD_WZ_EDIT_SEL=$(( SSHD_WZ_EDIT_SEL - 1 )) ;;
            DOWN|j|J|л|Л) (( SSHD_WZ_EDIT_SEL < ${#SSHD_WZ_EDIT_OPTIONS[@]} - 1 )) && SSHD_WZ_EDIT_SEL=$(( SSHD_WZ_EDIT_SEL + 1 )) ;;
            ENTER) sshd_wz::commit_edit ;;
            ESC|q|Q) tui::modal::close ;;
            *) : ;;
        esac
        return 0
    fi
    case "${TUI_KEY}" in
        ENTER) sshd_wz::commit_edit ;;
        ESC) tui::modal::close ;;
        BACKSPACE)
            (( SSHD_WZ_EDIT_CURSOR > 0 )) || return 0
            SSHD_WZ_EDIT_VALUE="${SSHD_WZ_EDIT_VALUE:0:SSHD_WZ_EDIT_CURSOR-1}${SSHD_WZ_EDIT_VALUE:SSHD_WZ_EDIT_CURSOR}"
            SSHD_WZ_EDIT_CURSOR=$(( SSHD_WZ_EDIT_CURSOR - 1 ))
            ;;
        LEFT)  (( SSHD_WZ_EDIT_CURSOR > 0 )) && SSHD_WZ_EDIT_CURSOR=$(( SSHD_WZ_EDIT_CURSOR - 1 )) ;;
        RIGHT) (( SSHD_WZ_EDIT_CURSOR < ${#SSHD_WZ_EDIT_VALUE} )) && SSHD_WZ_EDIT_CURSOR=$(( SSHD_WZ_EDIT_CURSOR + 1 )) ;;
        *)
            if [[ "${TUI_KEY}" =~ ^[[:print:]]+$ && ${#TUI_KEY} -eq 1 ]]; then
                SSHD_WZ_EDIT_VALUE="${SSHD_WZ_EDIT_VALUE:0:SSHD_WZ_EDIT_CURSOR}${TUI_KEY}${SSHD_WZ_EDIT_VALUE:SSHD_WZ_EDIT_CURSOR}"
                SSHD_WZ_EDIT_CURSOR=$(( SSHD_WZ_EDIT_CURSOR + 1 ))
            fi
            ;;
    esac
    return 0
}

# ==========================================
# Draw / Отрисовка
# ==========================================

sshd_wz::draw_title() {
    tui::titlebar "  BS sshd wizard  •  профиль/profile: ${SSHD_WZ_PROFILE}  •  цель/target: ${SSHD_WZ_TARGET}" "$(tui::style bold bg_blue white)"
}

sshd_wz::draw_sections() {
    tui::box 2 1 26 "${TUI_LINES_MINUS}" "Секции / Sections" "$(tui::style bold magenta)"
    local -i i
    for (( i = 0; i < ${#SSHD_WZ_SECTIONS[@]}; i++ )); do
        if (( i == SSHD_WZ_SECTION )); then
            tui::put $(( 3 + i )) 3 "▸ ${SSHD_WZ_SECTIONS[$i]}" "$(tui::style bold reverse white)"
        else
            tui::put $(( 3 + i )) 3 "  ${SSHD_WZ_SECTIONS[$i]}" ""
        fi
    done
}

sshd_wz::draw_params() {
    local -i top=2 left=28
    local -i width=$(( TUI_COLS - left - 1 ))
    local -i height=$(( TUI_LINES - 8 ))
    tui::box "${top}" "${left}" "${width}" "${height}" "Параметры / Parameters" "$(tui::style bold cyan)"
    local -i i row
    for (( i = 0; i < ${#SSHD_WZ_NAMES[@]}; i++ )); do
        row=$(( top + 1 + i ))
        (( row >= top + height - 1 )) && break
        local name="${SSHD_WZ_NAMES[$i]}"
        local value="${SSHD_WZ_VALUES[$name]:-}"
        local line="${name} = ${value}"
        if (( i == SSHD_WZ_SELECT )); then
            tui::put "${row}" $(( left + 2 )) "${line}" "$(tui::style bold reverse cyan)"
        elif is::not_empty "${value}"; then
            tui::put "${row}" $(( left + 2 )) "${line}" "$(tui::style green)"
        else
            tui::put "${row}" $(( left + 2 )) "${line}" "$(tui::style dim)"
        fi
    done
}

sshd_wz::draw_desc() {
    local -i top=$(( TUI_LINES - 5 ))
    local name="${SSHD_WZ_NAMES[$SSHD_WZ_SELECT]:-}"
    local desc=""
    is::not_empty "${name}" && desc="$(sshd::param_desc "${name}" 2>/dev/null || true)"
    tui::box "${top}" 1 "${TUI_COLS}" 5 "Подсказка / Tip: ${name}" "$(tui::style bold yellow)"
    local -a lines=()
    mapfile -t lines <<< "${desc}"
    tui::put $(( top + 1 )) 3 "${lines[0]:-}" ""
    tui::put $(( top + 2 )) 3 "${lines[1]:-}" "$(tui::style dim)"
}

sshd_wz::draw_status() {
    tui::statusbar "  ←→ секция · ↑↓ параметр · Enter правка · Space toggle · P профиль · V preview · A apply · ? справка · q выход" "$(tui::style bg_black white)"
}

sshd_wz::draw() {
    TUI_LINES_MINUS=$(( TUI_LINES - 7 ))
    sshd_wz::draw_title
    sshd_wz::draw_sections
    sshd_wz::draw_params
    sshd_wz::draw_desc
    sshd_wz::draw_status
}

# ==========================================
# Keys / Клавиши
# ==========================================

sshd_wz::handle_view_key() {
    case "${TUI_KEY}" in
        q|Q|й|Й) return 1 ;;
        LEFT)  (( SSHD_WZ_SECTION > 0 )) && { SSHD_WZ_SECTION=$(( SSHD_WZ_SECTION - 1 )); SSHD_WZ_SELECT=0; sshd_wz::load_names; } ;;
        RIGHT) (( SSHD_WZ_SECTION < ${#SSHD_WZ_SECTIONS[@]} - 1 )) && { SSHD_WZ_SECTION=$(( SSHD_WZ_SECTION + 1 )); SSHD_WZ_SELECT=0; sshd_wz::load_names; } ;;
        UP|k|K|о|О)   (( SSHD_WZ_SELECT > 0 )) && SSHD_WZ_SELECT=$(( SSHD_WZ_SELECT - 1 )) ;;
        DOWN|j|J|л|Л) (( SSHD_WZ_SELECT < ${#SSHD_WZ_NAMES[@]} - 1 )) && SSHD_WZ_SELECT=$(( SSHD_WZ_SELECT + 1 )) ;;
        *) : ;;
    esac
    return 0
}

# ==========================================
# Main loop / Главный цикл
# ==========================================

main() {
    local arg
    for arg in "$@"; do
        case "${arg}" in
            --help)
                printf 'BS sshd wizard — собирает sshd_config (drop-in или main).\n'
                printf 'Клавиши: ←→ ↑↓ Enter Space P V A ? q\n'
                return 0
                ;;
            --dry-run) BS_SSHD_DRY_RUN=1 ;;
        esac
    done
    sshd::init 2>/dev/null || true
    sshd_wz::load_sections
    sshd_wz::load_names
    tui::init
    local running=1 top
    while (( running )); do
        tui::handle_resize
        tui::buf::clear
        sshd_wz::draw
        tui::modal::draw_all
        tui::render
        tui::key_read
        top="$(tui::modal::top)"
        if is::not_empty "${top}"; then
            sshd_wz::handle_edit_key
        else
            case "${TUI_KEY}" in
                ENTER|SPACE) sshd_wz::begin_edit ;;
                *) sshd_wz::handle_view_key || running=0 ;;
            esac
        fi
    done
    tui::quit
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
