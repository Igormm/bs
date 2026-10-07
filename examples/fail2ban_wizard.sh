#!/usr/bin/env bs
# shellcheck shell=bash
# examples/fail2ban_wizard.sh — interactive TUI for building a fail2ban config
# examples/fail2ban_wizard.sh — интерактивный TUI для сборки конфига fail2ban
#
# Full-screen wizard on lib/tui/tui (same engine/UX as the sshd wizard):
# sections = [DEFAULT] + enabled jails. Left pane lists sections; center lists
# the section's parameters with values; bottom shows a two-line Russian tip for
# the selected parameter. J opens a jail picker (Space toggles). P cycles a
# hardening profile; V previews; A applies (drop-in or print).
# Полноэкранный визард на lib/tui/tui (тот же движок, что у sshd-визарда):
# секции = [DEFAULT] + включённые джейлы. Слева — секции, по центру — параметры
# секции со значениями, снизу — двухстрочная русская подсказка. J открывает
# выбор джейлов (Space — переключить). P — профиль, V — предпросмотр,
# A — применить (drop-in или печать).
#
# Run / Запуск:
#   bs run examples/fail2ban_wizard.sh [--dry-run] [--help]
#
# Keys / Клавиши:
#   ← меню · → параметры · ↑↓ выбор · Enter правка · Space toggle (в меню джейлов) ·
#   J джейлы · P профиль · T цель · V preview · A apply · ? справка · q выход

load "lib/system/fail2ban"
load "lib/tui/tui"

# ==========================================
# State / Состояние
# ==========================================

# @global F2B_WZ_SECTIONS — Fail2ban wizard: section names (category: state)
# @global F2B_WZ_SECTIONS — Визард fail2ban: имена секций (категория: state)
declare -ga F2B_WZ_SECTIONS=()
# @global F2B_WZ_NAMES — Fail2ban wizard: params of current section (category: state)
# @global F2B_WZ_NAMES — Визард fail2ban: параметры текущей секции (категория: state)
declare -ga F2B_WZ_NAMES=()
# @global F2B_WZ_VALUES — Fail2ban wizard: chosen section.param=value (category: state)
# @global F2B_WZ_VALUES — Визард fail2ban: значения section.param (категория: state)
declare -gA F2B_WZ_VALUES=()
# @global F2B_WZ_JAILS — Fail2ban wizard: detected jail names (category: state)
# @global F2B_WZ_JAILS — Визард fail2ban: обнаруженные джейлы (категория: state)
declare -ga F2B_WZ_JAILS=()
# @global F2B_WZ_JAIL_ON — Fail2ban wizard: enabled jail marks (category: state)
# @global F2B_WZ_JAIL_ON — Визард fail2ban: отметки включённых джейлов (категория: state)
declare -gA F2B_WZ_JAIL_ON=()
# @global F2B_WZ_SECTION — Fail2ban wizard: selected section index (category: state)
# @global F2B_WZ_SECTION — Визард fail2ban: индекс выбранной секции (категория: state)
declare -gi F2B_WZ_SECTION=0
# @global F2B_WZ_SELECT — Fail2ban wizard: selected param index (category: state)
# @global F2B_WZ_SELECT — Визард fail2ban: индекс выбранного параметра (категория: state)
declare -gi F2B_WZ_SELECT=0
# @global F2B_WZ_FOCUS — Fail2ban wizard: focused pane menu|params (category: state)
# @global F2B_WZ_FOCUS — Визард fail2ban: панель под фокусом (категория: state)
declare -g F2B_WZ_FOCUS="params"
# @global F2B_WZ_PROFILE — Fail2ban wizard: chosen profile (category: state)
# @global F2B_WZ_PROFILE — Визард fail2ban: выбранный профиль (категория: state)
declare -g F2B_WZ_PROFILE="custom"
# @global F2B_WZ_TARGET — Fail2ban wizard: apply target dropin|print (category: state)
# @global F2B_WZ_TARGET — Визард fail2ban: цель dropin|print (категория: state)
declare -g F2B_WZ_TARGET="dropin"
# @global F2B_WZ_STATUS — Fail2ban wizard: status message (category: state)
# @global F2B_WZ_STATUS — Визард fail2ban: сообщение статуса (категория: state)
declare -g F2B_WZ_STATUS=""
# @global F2B_WZ_JAIL_SEL — Fail2ban wizard: jail picker cursor (category: state)
# @global F2B_WZ_JAIL_SEL — Визард fail2ban: курсор выбора джейлов (категория: state)
declare -gi F2B_WZ_JAIL_SEL=0
# @global F2B_WZ_PARAMS_PAINTED — Fail2ban wizard: painted param rows (category: state)
# @global F2B_WZ_PARAMS_PAINTED — Визард fail2ban: нарисованных строк параметров (категория: state)
declare -gi F2B_WZ_PARAMS_PAINTED=0
# @global F2B_WZ_PAD — Fail2ban wizard: padding scratch (category: state)
# @global F2B_WZ_PAD — Визард fail2ban: буфер выравнивания (категория: state)
declare -g F2B_WZ_PAD=""
# @global F2B_WZ_EDIT_VALUE — Fail2ban wizard: input modal buffer (category: state)
# @global F2B_WZ_EDIT_VALUE — Визард fail2ban: буфер ввода (категория: state)
declare -g F2B_WZ_EDIT_VALUE=""
# @global F2B_WZ_EDIT_CURSOR — Fail2ban wizard: input modal cursor (category: state)
# @global F2B_WZ_EDIT_CURSOR — Визард fail2ban: курсор ввода (категория: state)
declare -gi F2B_WZ_EDIT_CURSOR=0
# @global F2B_WZ_EDIT_OPTIONS — Fail2ban wizard: choice options (category: state)
# @global F2B_WZ_EDIT_OPTIONS — Визард fail2ban: варианты выбора (категория: state)
declare -ga F2B_WZ_EDIT_OPTIONS=()
# @global F2B_WZ_EDIT_SEL — Fail2ban wizard: choice selection (category: state)
# @global F2B_WZ_EDIT_SEL — Визард fail2ban: выбранный вариант (категория: state)
declare -gi F2B_WZ_EDIT_SEL=0
# @global F2B_WZ_EDIT_ERR — Fail2ban wizard: validation error (category: state)
# @global F2B_WZ_EDIT_ERR — Визард fail2ban: ошибка валидации (категория: state)
declare -g F2B_WZ_EDIT_ERR=""
# @global F2B_WZ_EDIT_MODE — Fail2ban wizard: input|choice (category: state)
# @global F2B_WZ_EDIT_MODE — Визард fail2ban: input|choice (категория: state)
declare -g F2B_WZ_EDIT_MODE=""
# @global F2B_WZ_CONFIRM_SEL — Fail2ban wizard: confirm selection (category: state)
# @global F2B_WZ_CONFIRM_SEL — Визард fail2ban: выбор подтверждения (категория: state)
declare -gi F2B_WZ_CONFIRM_SEL=0
# @global F2B_WZ_SEC_LEN / F2B_WZ_PAR_LEN / F2B_WZ_DESC_LEN — painted text lengths (category: state)
# @global F2B_WZ_*_LEN — длины нарисованного текста (категория: state)
declare -gA F2B_WZ_SEC_LEN=()
declare -gA F2B_WZ_PAR_LEN=()
declare -gA F2B_WZ_DESC_LEN=()

# ==========================================
# State helpers / Помощники состояния
# ==========================================

# @private Param value / значение параметра
f2b_wz::value() { printf '%s' "${F2B_WZ_VALUES[${1}.${2}]:-}"; }

# @private Params of the current section / параметры текущей секции
f2b_wz::load_names() {
    F2B_WZ_NAMES=()
    local -r sec="${F2B_WZ_SECTIONS[$F2B_WZ_SECTION]:-}"
    if [[ "${sec}" == "DEFAULT" ]]; then
        F2B_WZ_NAMES=("${F2B_DEFAULT_ORDER[@]}")
    else
        F2B_WZ_NAMES=("${F2B_JAIL_ORDER[@]}")
    fi
    (( F2B_WZ_SELECT >= ${#F2B_WZ_NAMES[@]} )) && F2B_WZ_SELECT=0
    return 0
}

# @private Rebuild the section list: DEFAULT + enabled jails / перестроить секции
f2b_wz::rebuild_sections() {
    F2B_WZ_SECTIONS=("DEFAULT")
    local jail
    for jail in $(printf '%s\n' "${!F2B_WZ_JAIL_ON[@]}" | sort); do
        is::empty "${jail}" && continue
        [[ "${F2B_WZ_JAIL_ON[$jail]:-0}" == "1" ]] && F2B_WZ_SECTIONS+=("${jail}")
    done
    (( F2B_WZ_SECTION >= ${#F2B_WZ_SECTIONS[@]} )) && F2B_WZ_SECTION=0
    f2b_wz::load_names
    return 0
}

# @private Load detected jails into the picker / загрузить обнаруженные джейлы
f2b_wz::load_jails() {
    F2B_WZ_JAILS=()
    local j
    while IFS= read -r j; do
        is::not_empty "${j}" && F2B_WZ_JAILS+=("${j}")
    done < <(fail2ban::detect)
    if (( ${#F2B_WZ_JAILS[@]} == 0 )); then
        while IFS= read -r j; do is::not_empty "${j}" && F2B_WZ_JAILS+=("${j}"); done \
            < <(printf '%s\n' "${!F2B_JAILS[@]}" | sort)
    fi
    return 0
}

# @private Toggle a jail on/off (updates values + sections) / переключить джейл
f2b_wz::toggle_jail() {
    local -r jail="${F2B_WZ_JAILS[$F2B_WZ_JAIL_SEL]:-}"
    is::empty "${jail}" && return 0
    if [[ "${F2B_WZ_JAIL_ON[$jail]:-0}" == "1" ]]; then
        F2B_WZ_JAIL_ON["${jail}"]=0
        unset "F2B_WZ_VALUES[${jail}.enabled]"
    else
        F2B_WZ_JAIL_ON["${jail}"]=1
        F2B_WZ_VALUES["${jail}.enabled"]="true"
        # seed recommended filter/logpath/port / заполнить рекомендованное
        local rec="${F2B_JAILS[$jail]:-}"
        local -a parts=()
        IFS='|' read -ra parts <<< "${rec}"
        is::not_empty "${parts[0]:-}" && F2B_WZ_VALUES["${jail}.filter"]="${parts[0]}"
        is::not_empty "${parts[1]:-}" && F2B_WZ_VALUES["${jail}.logpath"]="${parts[1]}"
        is::not_empty "${parts[2]:-}" && F2B_WZ_VALUES["${jail}.port"]="${parts[2]}"
    fi
    f2b_wz::rebuild_sections
    return 0
}

# @private Apply a profile / применить профиль
# @param $1 basic|strict|paranoid|custom
f2b_wz::apply_profile() {
    local -r profile="${1:?profile required}"
    F2B_WZ_PROFILE="${profile}"
    [[ "${profile}" == "custom" ]] && return 0
    local line sec param key val
    while IFS= read -r line; do
        is::empty "${line}" && continue
        key="${line%%=*}"; val="${line#*=}"
        sec="${key%%.*}"; param="${key#*.}"
        F2B_WZ_VALUES["${sec}.${param}"]="${val}"
        if [[ "${sec}" != "DEFAULT" && "${param}" == "enabled" && "${val}" == "true" ]]; then
            F2B_WZ_JAIL_ON["${sec}"]=1
        fi
    done < <(fail2ban::profile "${profile}")
    f2b_wz::rebuild_sections
    return 0
}

# @private Render current values as INI text / отрендерить текущие значения
f2b_wz::render_config() {
    local sec name v
    {
        printf '@section DEFAULT\n'
        for name in "${F2B_DEFAULT_ORDER[@]}"; do
            v="${F2B_WZ_VALUES[DEFAULT.${name}]:-}"
            is::not_empty "${v}" || continue
            printf '%s=%s\n' "${name}" "${v}"
        done
        for sec in $(printf '%s\n' "${!F2B_WZ_JAIL_ON[@]}" | sort); do
            is::empty "${sec}" && continue
            [[ "${F2B_WZ_JAIL_ON[$sec]:-0}" == "1" ]] || continue
            printf '\n@section %s\n' "${sec}"
            for name in "${F2B_JAIL_ORDER[@]}"; do
                v="${F2B_WZ_VALUES[${sec}.${name}]:-}"
                is::not_empty "${v}" || continue
                printf '%s=%s\n' "${name}" "${v}"
            done
        done
        :
    } | fail2ban::render
}

# ==========================================
# Styles / Стили
# ==========================================

# @global F2B_ST_* — Fail2ban wizard: cached SGR styles (category: state)
# @global F2B_ST_* — Визард fail2ban: кеш SGR-стилей (категория: state)
declare -g F2B_ST_TITLE="" F2B_ST_SEC="" F2B_ST_PAR="" F2B_ST_DESC="" \
    F2B_ST_OK="" F2B_ST_DIM="" F2B_ST_SEL="" F2B_ST_SEL_OFF="" \
    F2B_ST_STATUS="" F2B_ST_RED=""

f2b_wz::cache_styles() {
    F2B_ST_TITLE="$(tui::style bold bg_blue white)"
    F2B_ST_SEC="$(tui::style bold magenta)"
    F2B_ST_PAR="$(tui::style bold cyan)"
    F2B_ST_DESC="$(tui::style bold yellow)"
    F2B_ST_OK="$(tui::style green)"
    F2B_ST_DIM="$(tui::style dim)"
    F2B_ST_SEL="$(tui::style bold reverse cyan)"
    F2B_ST_SEL_OFF="$(tui::style reverse)"
    F2B_ST_STATUS="$(tui::style bg_black white)"
    F2B_ST_RED="$(tui::style bold red)"
    return 0
}

# ==========================================
# Draw / Отрисовка
# ==========================================

# @private Put a row, erasing a longer previous tail / строка с затиранием хвоста
f2b_wz::put_row() {
    local -i r="$1" c="$2"
    local text="$3" st="$4"
    local -n __lenmap="$5"
    local key="$6"
    local -i prev="${__lenmap[${key}]:-0}" len=${#text}
    tui::put "${r}" "${c}" "${text}" "${st}"
    if (( prev > len )); then
        printf -v F2B_WZ_PAD '%*s' $(( prev - len )) ''
        tui::put "${r}" $(( c + len )) "${F2B_WZ_PAD}" ""
    fi
    __lenmap["${key}"]="${len}"
    return 0
}

f2b_wz::draw_title() {
    tui::titlebar "  BS fail2ban wizard  •  профиль/profile: ${F2B_WZ_PROFILE}  •  цель/target: ${F2B_WZ_TARGET}" "${F2B_ST_TITLE}"
}

f2b_wz::paint_section_row() {
    local -i i="$1"
    local -i row=$(( 3 + i ))
    local name="${F2B_WZ_SECTIONS[$i]:-}"
    local text="  ${name}" st=""
    if (( i == F2B_WZ_SECTION )); then
        text="▸ ${name}"
        if [[ "${F2B_WZ_FOCUS}" == "menu" ]]; then st="${F2B_ST_SEL}"; else st="${F2B_ST_SEL_OFF}"; fi
    fi
    f2b_wz::put_row "${row}" 3 "${text}" "${st}" F2B_WZ_SEC_LEN "${i}"
}

f2b_wz::draw_sections() {
    tui::box 2 1 30 "$(( TUI_LINES - 7 ))" "Секции / Sections" "${F2B_ST_SEC}"
    local -i i
    for (( i = 0; i < ${#F2B_WZ_SECTIONS[@]}; i++ )); do
        f2b_wz::paint_section_row "${i}"
    done
}

f2b_wz::paint_param_row() {
    local -i i="$1"
    local -i row=$(( 3 + i ))
    local -i inner=$(( TUI_COLS - 36 ))
    local name="${F2B_WZ_NAMES[$i]:-}"
    local text="" st=""
    if is::not_empty "${name}"; then
        local value; value="$(f2b_wz::value "${F2B_WZ_SECTIONS[$F2B_WZ_SECTION]:-}" "${name}")"
        text="${name} = ${value}"
        if (( i == F2B_WZ_SELECT )); then
            if [[ "${F2B_WZ_FOCUS}" == "params" ]]; then st="${F2B_ST_SEL}"; else st="${F2B_ST_SEL_OFF}"; fi
        elif is::not_empty "${value}"; then st="${F2B_ST_OK}"
        else st="${F2B_ST_DIM}"; fi
    fi
    f2b_wz::put_row "${row}" 34 "${text}" "${st}" F2B_WZ_PAR_LEN "${i}"
}

f2b_wz::paint_params_rows() {
    local -i n=${#F2B_WZ_NAMES[@]}
    local -i total=$(( n > F2B_WZ_PARAMS_PAINTED ? n : F2B_WZ_PARAMS_PAINTED ))
    local -i i
    for (( i = 0; i < total; i++ )); do f2b_wz::paint_param_row "${i}"; done
    F2B_WZ_PARAMS_PAINTED=$n
    return 0
}

f2b_wz::draw_params() {
    local -i left=32
    tui::box 2 "${left}" "$(( TUI_COLS - left - 1 ))" "$(( TUI_LINES - 8 ))" "Параметры / Parameters" "${F2B_ST_PAR}"
    f2b_wz::paint_params_rows
}

f2b_wz::paint_desc_rows() {
    local -i top=$(( TUI_LINES - 5 ))
    local -r sec="${F2B_WZ_SECTIONS[$F2B_WZ_SECTION]:-}"
    local name="${F2B_WZ_NAMES[$F2B_WZ_SELECT]:-}"
    local tip=""
    is::not_empty "${name}" && tip="${F2B_TIPS[$name]:-}"
    local -a lines=(); mapfile -t lines <<< "${tip}"
    f2b_wz::put_row $(( top + 1 )) 3 "Параметр: ${sec}.${name}" "${F2B_ST_DIM}" F2B_WZ_DESC_LEN 0
    f2b_wz::put_row $(( top + 2 )) 3 "${lines[0]:-}" "" F2B_WZ_DESC_LEN 1
    f2b_wz::put_row $(( top + 3 )) 3 "${lines[1]:-}" "${F2B_ST_DIM}" F2B_WZ_DESC_LEN 2
    return 0
}

f2b_wz::draw_desc() {
    tui::box $(( TUI_LINES - 5 )) 1 "${TUI_COLS}" 5 "Подсказка / Tip" "${F2B_ST_DESC}"
    f2b_wz::paint_desc_rows
}
f2b_wz::update_desc() { f2b_wz::paint_desc_rows; }

f2b_wz::draw_status() {
    local hint
    if [[ "${F2B_WZ_FOCUS}" == "menu" ]]; then
        hint="  ↑↓ секция · → параметры · J джейлы · P профиль · V preview · A apply · ? справка · q выход"
    else
        hint="  ↑↓ параметр · ← меню · Enter правка · J джейлы · T цель · V preview · A apply · q выход"
    fi
    tui::statusbar "${hint}" "${F2B_ST_STATUS}"
}

f2b_wz::paint_all() {
    tui::border::set single
    f2b_wz::cache_styles
    tui::buf::clear
    F2B_WZ_PARAMS_PAINTED=0
    F2B_WZ_SEC_LEN=(); F2B_WZ_PAR_LEN=(); F2B_WZ_DESC_LEN=()
    f2b_wz::draw_title
    f2b_wz::draw_sections
    f2b_wz::draw_params
    f2b_wz::draw_desc
    f2b_wz::draw_status
}
f2b_wz::draw() { f2b_wz::paint_all; }

# ==========================================
# Editing / Редактирование
# ==========================================

f2b_wz::begin_edit() {
    local -r sec="${F2B_WZ_SECTIONS[$F2B_WZ_SECTION]:-}"
    local -r name="${F2B_WZ_NAMES[$F2B_WZ_SELECT]:-}"
    is::empty "${name}" && return 0
    F2B_WZ_EDIT_ERR=""; F2B_WZ_EDIT_SEL=0
    local -r type="$(fail2ban::param_type "${name}")"
    local current="${F2B_WZ_VALUES[${sec}.${name}]:-$(fail2ban::param_default "${name}")}"
    case "${type}" in
        bool) F2B_WZ_EDIT_OPTIONS=("true" "false") ;;
        enum:*) IFS=',' read -ra F2B_WZ_EDIT_OPTIONS <<< "${type#enum:}" ;;
        *) F2B_WZ_EDIT_OPTIONS=() ;;
    esac
    if (( ${#F2B_WZ_EDIT_OPTIONS[@]} > 0 )); then
        F2B_WZ_EDIT_MODE="choice"
        local i
        for i in "${!F2B_WZ_EDIT_OPTIONS[@]}"; do
            [[ "${F2B_WZ_EDIT_OPTIONS[$i]}" == "${current}" ]] && F2B_WZ_EDIT_SEL=$i
        done
    else
        F2B_WZ_EDIT_MODE="input"
        F2B_WZ_EDIT_VALUE="${current}"
        F2B_WZ_EDIT_CURSOR=${#current}
    fi
    tui::modal::open edit f2b_wz::modal_edit_draw
    return 0
}

f2b_wz::commit_edit() {
    local -r sec="${F2B_WZ_SECTIONS[$F2B_WZ_SECTION]:-}"
    local -r name="${F2B_WZ_NAMES[$F2B_WZ_SELECT]:-}"
    local value="${F2B_WZ_EDIT_VALUE}"
    (( ${#F2B_WZ_EDIT_OPTIONS[@]} > 0 )) && value="${F2B_WZ_EDIT_OPTIONS[$F2B_WZ_EDIT_SEL]}"
    if fail2ban::validate "${name}" "${value}"; then
        F2B_WZ_VALUES["${sec}.${name}"]="${value}"
        F2B_WZ_EDIT_ERR=""
        tui::modal::close
    else
        F2B_WZ_EDIT_ERR="Недопустимое значение / invalid: ${value}"
    fi
    return 0
}

f2b_wz::modal_edit_draw() {
    local -i w=64 h=8
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local -r name="${F2B_WZ_NAMES[$F2B_WZ_SELECT]:-}"
    tui::box "${by}" "${bx}" "${w}" "${h}" "Правка / Edit: ${name}" "${F2B_ST_PAR}"
    if [[ "${F2B_WZ_EDIT_MODE}" == "choice" ]]; then
        local i
        for i in "${!F2B_WZ_EDIT_OPTIONS[@]}"; do
            if (( i == F2B_WZ_EDIT_SEL )); then
                tui::put $(( by + 1 + i )) $(( bx + 2 )) "▸ ${F2B_WZ_EDIT_OPTIONS[$i]}" "${F2B_ST_SEL}"
            else
                tui::put $(( by + 1 + i )) $(( bx + 2 )) "  ${F2B_WZ_EDIT_OPTIONS[$i]}" ""
            fi
        done
    else
        tui::put $(( by + 2 )) $(( bx + 2 )) "Значение / Value:" ""
        tui::input $(( by + 3 )) $(( bx + 2 )) $(( w - 4 )) "${F2B_WZ_EDIT_VALUE}" "${F2B_WZ_EDIT_CURSOR}"
    fi
    is::not_empty "${F2B_WZ_EDIT_ERR}" && tui::put $(( by + h - 2 )) $(( bx + 2 )) "${F2B_WZ_EDIT_ERR}" "${F2B_ST_RED}"
    tui::put $(( by + h - 1 )) $(( bx + 2 )) "Enter — OK · Esc — отмена" "${F2B_ST_DIM}"
}

f2b_wz::handle_edit_key() {
    if [[ "${F2B_WZ_EDIT_MODE}" == "choice" ]]; then
        case "${TUI_KEY}" in
            UP|k|K|о|О)   (( F2B_WZ_EDIT_SEL > 0 )) && F2B_WZ_EDIT_SEL=$(( F2B_WZ_EDIT_SEL - 1 )) ;;
            DOWN|j|J|л|Л) (( F2B_WZ_EDIT_SEL < ${#F2B_WZ_EDIT_OPTIONS[@]} - 1 )) && F2B_WZ_EDIT_SEL=$(( F2B_WZ_EDIT_SEL + 1 )) ;;
            ENTER) f2b_wz::commit_edit ;;
            ESC|q|Q) tui::modal::close ;;
            *) : ;;
        esac
        return 0
    fi
    case "${TUI_KEY}" in
        ENTER) f2b_wz::commit_edit ;;
        ESC) tui::modal::close ;;
        BACKSPACE)
            (( F2B_WZ_EDIT_CURSOR > 0 )) || return 0
            F2B_WZ_EDIT_VALUE="${F2B_WZ_EDIT_VALUE:0:F2B_WZ_EDIT_CURSOR-1}${F2B_WZ_EDIT_VALUE:F2B_WZ_EDIT_CURSOR}"
            F2B_WZ_EDIT_CURSOR=$(( F2B_WZ_EDIT_CURSOR - 1 )) ;;
        LEFT)  (( F2B_WZ_EDIT_CURSOR > 0 )) && F2B_WZ_EDIT_CURSOR=$(( F2B_WZ_EDIT_CURSOR - 1 )) ;;
        RIGHT) (( F2B_WZ_EDIT_CURSOR < ${#F2B_WZ_EDIT_VALUE} )) && F2B_WZ_EDIT_CURSOR=$(( F2B_WZ_EDIT_CURSOR + 1 )) ;;
        *)
            if [[ "${TUI_KEY}" =~ ^[[:print:]]+$ && ${#TUI_KEY} -eq 1 ]]; then
                F2B_WZ_EDIT_VALUE="${F2B_WZ_EDIT_VALUE:0:F2B_WZ_EDIT_CURSOR}${TUI_KEY}${F2B_WZ_EDIT_VALUE:F2B_WZ_EDIT_CURSOR}"
                F2B_WZ_EDIT_CURSOR=$(( F2B_WZ_EDIT_CURSOR + 1 ))
            fi ;;
    esac
    return 0
}

# ==========================================
# Jail picker modal / Модалка выбора джейлов
# ==========================================

f2b_wz::open_jails() { F2B_WZ_JAIL_SEL=0; tui::modal::open jails f2b_wz::modal_jails_draw; }

f2b_wz::modal_jails_draw() {
    local -i w=64 h=$(( TUI_LINES - 6 ))
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}" i
    tui::box "${by}" "${bx}" "${w}" "${h}" "Джейлы / Jails" "${F2B_ST_SEC}"
    local -i visible=$(( h - 3 )) offset=0
    (( F2B_WZ_JAIL_SEL >= offset + visible )) && offset=$(( F2B_WZ_JAIL_SEL - visible + 1 ))
    for (( i = 0; i < visible; i++ )); do
        local idx=$(( offset + i ))
        (( idx < ${#F2B_WZ_JAILS[@]} )) || break
        local jail="${F2B_WZ_JAILS[$idx]}"
        local mark='○'; [[ "${F2B_WZ_JAIL_ON[$jail]:-0}" == "1" ]] && mark='●'
        if (( idx == F2B_WZ_JAIL_SEL )); then
            tui::put $(( by + 1 + i )) $(( bx + 2 )) "▸ ${mark} ${jail}" "${F2B_ST_SEL}"
        else
            tui::put $(( by + 1 + i )) $(( bx + 2 )) "  ${mark} ${jail}" ""
        fi
    done
    tui::put $(( by + h - 1 )) $(( bx + 2 )) "Space — вкл/выкл · Enter/Esc — закрыть" "${F2B_ST_DIM}"
}

f2b_wz::handle_jails_key() {
    case "${TUI_KEY}" in
        UP|k|K|о|О)   (( F2B_WZ_JAIL_SEL > 0 )) && F2B_WZ_JAIL_SEL=$(( F2B_WZ_JAIL_SEL - 1 )) ;;
        DOWN|j|J|л|Л) (( F2B_WZ_JAIL_SEL < ${#F2B_WZ_JAILS[@]} - 1 )) && F2B_WZ_JAIL_SEL=$(( F2B_WZ_JAIL_SEL + 1 )) ;;
        SPACE|' ')    f2b_wz::toggle_jail ;;
        ENTER|ESC|q|Q) tui::modal::close ;;
        *) : ;;
    esac
    return 0
}

# ==========================================
# Preview / Apply / Просмотр и применение
# ==========================================

f2b_wz::draw_preview() {
    local text; text="$(f2b_wz::render_config)"
    local -i w=$(( TUI_COLS - 4 )) h=$(( TUI_LINES - 2 ))
    tui::box 1 1 "${w}" "${h}" "Предпросмотр / Preview" "${F2B_ST_OK}"
    local -a lines=(); mapfile -t lines <<< "${text}"
    local -i i
    for (( i = 0; i < h - 2 && i < ${#lines[@]}; i++ )); do
        tui::put $(( 2 + i )) 3 "${lines[$i]:0:$(( w - 4 ))}" ""
    done
}
f2b_wz::open_preview() { tui::modal::open preview f2b_wz::draw_preview; }

f2b_wz::modal_result_draw() {
    local -i w=64 h=6
    tui::center "${w}" "${h}"
    tui::box "${TUI_CENTER_Y}" "${TUI_CENTER_X}" "${w}" "${h}" "Результат / Result" "${F2B_ST_PAR}"
    tui::put $(( TUI_CENTER_Y + 2 )) $(( TUI_CENTER_X + 2 )) "${F2B_WZ_STATUS:0:$(( w - 4 ))}" ""
    tui::put $(( TUI_CENTER_Y + 4 )) $(( TUI_CENTER_X + 2 )) "Enter — закрыть / close" "${F2B_ST_DIM}"
}

f2b_wz::apply() {
    if [[ "${F2B_WZ_TARGET}" == "print" ]]; then
        f2b_wz::open_preview
        return 0
    fi
    F2B_WZ_CONFIRM_SEL=1   # default No / по умолчанию Нет
    tui::modal::open confirm f2b_wz::modal_confirm_draw
    return 0
}
f2b_wz::modal_confirm_draw() {
    tui::confirm "Применить / Apply" "Записать в ${BS_FAIL2BAN_DROPIN} и reload? / write and reload?" "${F2B_WZ_CONFIRM_SEL}"
}

f2b_wz::do_apply() {
    local -r tmpf="$(mktemp "${TMPDIR:-/tmp}/bs-f2b-wizard.XXXXXX.conf")"
    f2b_wz::render_config > "${tmpf}"
    local rc=0
    fail2ban::install "${tmpf}" || rc=$?
    rm -f -- "${tmpf}"
    if (( rc == 0 )); then
        F2B_WZ_STATUS="Установлено / Installed (${BS_FAIL2BAN_DROPIN})"
    else
        F2B_WZ_STATUS="Ошибка / Error: ${rc}"
    fi
    tui::modal::open result f2b_wz::modal_result_draw
    return 0
}

f2b_wz::handle_confirm_key() {
    case "${TUI_KEY}" in
        ENTER) tui::modal::close; (( F2B_WZ_CONFIRM_SEL == 0 )) && f2b_wz::do_apply ;;
        ESC|n|N|н|Н) tui::modal::close ;;
        LEFT|RIGHT|TAB) F2B_WZ_CONFIRM_SEL=$(( 1 - F2B_WZ_CONFIRM_SEL )) ;;
        y|Y|д|Д) tui::modal::close; f2b_wz::do_apply ;;
        *) : ;;
    esac
    return 0
}

f2b_wz::cycle_target() {
    [[ "${F2B_WZ_TARGET}" == "dropin" ]] && F2B_WZ_TARGET="print" || F2B_WZ_TARGET="dropin"
    return 0
}

f2b_wz::cycle_profile() {
    case "${F2B_WZ_PROFILE}" in
        custom)   f2b_wz::apply_profile basic ;;
        basic)    f2b_wz::apply_profile strict ;;
        strict)   f2b_wz::apply_profile paranoid ;;
        paranoid) f2b_wz::apply_profile custom ;;
        *)        f2b_wz::apply_profile basic ;;
    esac
    return 0
}

# ==========================================
# Help / Справка
# ==========================================

f2b_wz::draw_help() {
    local -i w=72 h=13
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    tui::box "${by}" "${bx}" "${w}" "${h}" "Справка / Help" "${F2B_ST_PAR}"
    local -a rows=(
        "← — фокус в меню секций / focus sections menu"
        "→ — фокус в параметры / focus parameters"
        "↑↓ — выбор в панели под фокусом / move in focused pane"
        "Enter — правка значения / edit value"
        "J — выбор джейлов (Space — вкл/выкл) / pick jails"
        "P — профиль basic/strict/paranoid/custom"
        "T — цель dropin/print · V — предпросмотр / preview"
        "A — применить (confirm) / apply"
        "q — выход / quit"
    )
    local -i i
    for (( i = 0; i < ${#rows[@]}; i++ )); do
        tui::put $(( by + 1 + i )) $(( bx + 2 )) "${rows[$i]}" ""
    done
    tui::put $(( by + h - 1 )) $(( bx + 2 )) "Enter/Esc — закрыть / close" "${F2B_ST_DIM}"
}

# ==========================================
# Keys / Клавиши
# ==========================================

f2b_wz::repaint_selection() {
    f2b_wz::paint_section_row "${F2B_WZ_SECTION}"
    f2b_wz::paint_param_row "${F2B_WZ_SELECT}"
}

f2b_wz::move_selection() {
    local -i d="$1"
    if [[ "${F2B_WZ_FOCUS}" == "menu" ]]; then
        local -i old="${F2B_WZ_SECTION}" n=${#F2B_WZ_SECTIONS[@]} new=$(( F2B_WZ_SECTION + d ))
        (( new < 0 || new >= n )) && return 0
        F2B_WZ_SECTION=$new; F2B_WZ_SELECT=0
        f2b_wz::load_names
        f2b_wz::paint_section_row "$old"
        f2b_wz::paint_section_row "$new"
        f2b_wz::paint_params_rows
        f2b_wz::update_desc
    else
        local -i old="${F2B_WZ_SELECT}" n=${#F2B_WZ_NAMES[@]} new=$(( F2B_WZ_SELECT + d ))
        (( new < 0 || new >= n )) && return 0
        F2B_WZ_SELECT=$new
        f2b_wz::paint_param_row "$old"
        f2b_wz::paint_param_row "$new"
        f2b_wz::update_desc
    fi
    return 0
}

f2b_wz::set_focus() {
    local -r f="$1"
    [[ "${f}" == "${F2B_WZ_FOCUS}" ]] && return 0
    F2B_WZ_FOCUS="${f}"
    f2b_wz::repaint_selection
    f2b_wz::draw_status
    return 0
}

f2b_wz::handle_view_key() {
    case "${TUI_KEY}" in
        q|Q|й|Й) return 1 ;;
        LEFT)  f2b_wz::set_focus menu ;;
        RIGHT) f2b_wz::set_focus params ;;
        UP|k|K|о|О)   f2b_wz::move_selection -1 ;;
        DOWN|j|J|л|Л) f2b_wz::move_selection 1 ;;
        ENTER)
            if [[ "${F2B_WZ_FOCUS}" == "menu" ]]; then f2b_wz::set_focus params; else f2b_wz::begin_edit; fi
            ;;
        J) f2b_wz::open_jails ;;
        V|v) f2b_wz::open_preview ;;
        A|a) f2b_wz::apply ;;
        P|p) f2b_wz::cycle_profile; f2b_wz::draw_title; f2b_wz::paint_params_rows; f2b_wz::update_desc ;;
        T|t) f2b_wz::cycle_target; f2b_wz::draw_title ;;
        '?') tui::modal::open help f2b_wz::draw_help ;;
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
                printf 'BS fail2ban wizard — собирает jail-конфиг fail2ban (drop-in или печать).\n'
                printf 'Клавиши: ← меню · → параметры · ↑↓ выбор · Enter правка · J джейлы · P профиль · T цель · V preview · A apply · ? справка · q выход\n'
                return 0
                ;;
            --dry-run) BS_FAIL2BAN_DRY_RUN=1 ;;
        esac
    done
    fail2ban::init 2>/dev/null || true
    f2b_wz::load_jails
    F2B_WZ_JAIL_ON["sshd"]=1
    F2B_WZ_VALUES["sshd.enabled"]="true"
    f2b_wz::rebuild_sections
    tui::init
    f2b_wz::paint_all
    local running=1 top top_before
    while (( running )); do
        if (( TUI_RESIZED == 1 )); then tui::handle_resize; f2b_wz::paint_all; fi
        tui::modal::draw_all
        tui::render
        tui::key_read

        top_before="$(tui::modal::top)"
        if [[ "${top_before}" == "edit" ]]; then
            f2b_wz::handle_edit_key
        elif [[ "${top_before}" == "jails" ]]; then
            f2b_wz::handle_jails_key
        elif [[ "${top_before}" == "confirm" ]]; then
            f2b_wz::handle_confirm_key
        elif is::not_empty "${top_before}"; then
            case "${TUI_KEY}" in ENTER|ESC|q|Q) tui::modal::close ;; *) : ;; esac
        else
            f2b_wz::handle_view_key || running=0
        fi
        top="$(tui::modal::top)"
        if [[ "${top_before}" != "${top}" && -n "${top_before}" ]]; then f2b_wz::paint_all; fi
    done
    tui::quit
}

if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
