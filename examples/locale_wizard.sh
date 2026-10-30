#!/usr/bin/env bs
# shellcheck shell=bash
# examples/locale_wizard.sh — localization, encoding and keyboard TUI wizard
# examples/locale_wizard.sh — TUI-визард локализации, кодировки и раскладки клавиатуры
#
# Полноэкранный визард (lib/tui): четыре шага — локаль (язык+страна), кодировка,
# раскладка клавиатуры (layout/model/variant/options) и просмотр+применение. Требует
# root (localectl пишет системную конфигурацию). Портабельная версия:
#   bs build examples/locale_wizard.sh --output bs-locale-wizard
# A full-screen wizard (lib/tui): four steps — locale (language+country), encoding,
# keyboard (layout/model/variant/options) and review+apply. Requires root (localectl
# writes the system configuration). Portable build:
#   bs build examples/locale_wizard.sh --output bs-locale-wizard
#
# Клавиши / Keys:
#   ←→ Tab      переключение секции / switch section
#   ↑↓ j k      выбор / select
#   Enter       выбрать/применить / choose/apply
#   o           ввести вручную (поле «Other…») / enter manually ("Other…")
#   q           выход / quit

load "lib/tui/tui"
load "lib/system/locale"
load "lib/system/keyboard"
load "lib/system/utils"

# Data / Данные

declare -a SECTIONS=("Locale" "Encoding" "Keyboard" "Review")

declare -a BASE_LOCALES=(
  en_US en_GB ru_RU de_DE fr_FR es_ES it_IT pt_BR pt_PT uk_UA be_BY kk_KZ
  tr_TR pl_PL cs_CZ sk_SK hu_HU ro_RO bg_BG sr_RS hr_HR sl_SI el_GR nl_NL
  sv_SE no_NO da_DK fi_FI et_EE lv_LV lt_LT ja_JP zh_CN ko_KR ar_SA he_IL hi_IN
  "Other…"
)
declare -a ENCODINGS=(UTF-8 ISO-8859-1 ISO-8859-15 CP1251 KOI8-R)
declare -a KBFIELDS=("Layout" "Model" "Variant" "Options")

declare -a KB_LAYOUTS=(us ru de fr es it pt br gb ua by kz tr pl cz sk hu ro bg rs hr si el nl se no dk "fi" ee lv lt jp cn kr "Other…")
declare -a KB_MODELS=(pc105 pc104 pc101 macintosh thinkpad "Other…")
declare -a KB_VARIANTS=("(none)" dvorak colemak "ru-phonetic" "Other…")
declare -a KB_OPTIONS=("(none)" ctrl:swapcaps caps:escape ctrl:nocaps "Other…")

# State / Состояние

declare -i SECTION=0
declare -i SEL=0

BASE="en_US"
ENCODING="UTF-8"
LAYOUT="us"
MODEL="pc105"
VARIANT=""
OPTIONS=""

INPUT_LABEL=""
INPUT_VALUE=""
INPUT_CURSOR=0
INPUT_TARGET=""             # base | layout | model | variant | options

PICKER_FIELD=""             # layout | model | variant | options
declare -a PICKER_VALS=()
declare -i PICKER_SEL=0

CONFIRM_SEL=0

# Helpers / Помощники

wiz::sec_len() {
    case "${SECTION}" in
        0) printf '%s' "${#BASE_LOCALES[@]}" ;;
        1) printf '%s' "${#ENCODINGS[@]}" ;;
        2) printf '%s' "${#KBFIELDS[@]}" ;;
        *) printf '1' ;;
    esac
}

wiz::sel_value() {
    # текущее значение по секции и индексу / the current value by section and index
    case "${SECTION}" in
        0) [[ "${SEL}" -lt ${#BASE_LOCALES[@]} ]] && printf '%s' "${BASE_LOCALES[${SEL}]}" ;;
        1) [[ "${SEL}" -lt ${#ENCODINGS[@]} ]] && printf '%s' "${ENCODINGS[${SEL}]}" ;;
    esac
    return 0
}

wiz::kb_value() {
    case "${PICKER_FIELD}" in
        layout)  printf '%s' "${LAYOUT}" ;;
        model)   printf '%s' "${MODEL}" ;;
        variant) printf '%s' "${VARIANT}" ;;
        options) printf '%s' "${OPTIONS}" ;;
    esac
}

wiz::kb_show() {
    # значение для отображения (пустое — «none») / the display value (empty = "none")
    local v
    case "${1}" in
        layout)  v="${LAYOUT}" ;;
        model)   v="${MODEL}" ;;
        variant) v="${VARIANT}" ;;
        options) v="${OPTIONS}" ;;
    esac
    [[ -z "${v}" ]] && v="(none)"
    printf '%s' "${v}"
}

wiz::set_kb() {
    case "${PICKER_FIELD}" in
        layout)  LAYOUT="${1}" ;;
        model)   MODEL="${1}" ;;
        variant) VARIANT="${1}" ;;
        options) OPTIONS="${1}" ;;
    esac
}

wiz::picker_values() {
    PICKER_VALS=()
    case "${PICKER_FIELD}" in
        layout)  PICKER_VALS=("${KB_LAYOUTS[@]}") ;;
        model)   PICKER_VALS=("${KB_MODELS[@]}") ;;
        variant) PICKER_VALS=("${KB_VARIANTS[@]}") ;;
        options) PICKER_VALS=("${KB_OPTIONS[@]}") ;;
    esac
}

# Draw / Отрисовка

wiz::draw_sidebar() {
    local -i i
    tui::box 2 1 20 7 "Steps" "$(tui::style bold magenta)"
    for (( i = 0; i < ${#SECTIONS[@]}; i++ )); do
        if (( i == SECTION )); then
            tui::put $(( 3 + i )) 3 "▸ ${SECTIONS[${i}]}" "$(tui::style bold reverse white)"
        else
            tui::put $(( 3 + i )) 3 "  ${SECTIONS[${i}]}" ""
        fi
    done
}

wiz::draw_list_box() {
    local -r title="$1"
    local -n vals="$2"
    local -n sel="$3"
    local -i i total=${#vals[@]}
    tui::box 2 23 56 $(( TUI_LINES - 4 )) "${title}" "$(tui::style bold cyan)"
    if (( total == 0 )); then
        tui::put 4 25 "empty" "$(tui::style dim)"
        return 0
    fi
    local -i vis=$(( TUI_LINES - 6 )) offset=0 idx
    (( sel < offset )) && offset="${sel}"
    (( sel >= offset + vis )) && offset=$(( sel - vis + 1 ))
    for (( i = 0; i < vis; i++ )); do
        idx=$(( offset + i ))
        (( idx >= total )) && break
        local line="${vals[${idx}]}"
        if (( idx == sel )); then
            tui::put $(( 3 + i )) 25 "▸ ${line:0:52}" "$(tui::style bold reverse cyan)"
        else
            tui::put $(( 3 + i )) 25 "  ${line:0:52}" ""
        fi
    done
    return 0
}

wiz::draw_locale() {
    wiz::draw_list_box "Locale (${BASE}.${ENCODING})" "BASE_LOCALES" "SEL"
}

wiz::draw_encoding() {
    wiz::draw_list_box "Encoding" "ENCODINGS" "SEL"
}

wiz::draw_keyboard() {
    local -i i
    tui::box 2 23 56 $(( TUI_LINES - 4 )) "Keyboard" "$(tui::style bold cyan)"
    local -i total=${#KBFIELDS[@]}
    for (( i = 0; i < total; i++ )); do
        local label
        label="${KBFIELDS[${i}]}: $(wiz::kb_show "${KBFIELDS[${i}],,}")"
        if (( i == SEL )); then
            tui::put $(( 3 + i )) 25 "▸ ${label:0:52}" "$(tui::style bold reverse cyan)"
        else
            tui::put $(( 3 + i )) 25 "  ${label:0:52}" ""
        fi
    done
}

wiz::draw_review() {
    tui::box 2 23 56 $(( TUI_LINES - 4 )) "Review & apply" "$(tui::style bold green)"
    tui::put 4 25 "Locale:   ${BASE}.${ENCODING}" "$(tui::style bold)"
    tui::put 5 25 "Keyboard: ${LAYOUT} / ${MODEL}" "$(tui::style bold)"
    [[ -n "${VARIANT}" ]] && tui::put 6 25 "Variant:  ${VARIANT}" "$(tui::style bold)"
    [[ -n "${OPTIONS}" ]] && tui::put 7 25 "Options:  ${OPTIONS}" "$(tui::style bold)"
    tui::put 9 25 "Press Enter to apply / Enter — применить" "$(tui::style dim)"
    tui::put 10 25 "localectl set-locale LANG=${BASE}.${ENCODING}" "$(tui::style dim)"
    tui::put 11 25 "localectl set-keymap ${LAYOUT}" "$(tui::style dim)"
}

wiz::draw_frame() {
    tui::titlebar "  BS Locale Wizard • ${TUI_COLS}x${TUI_LINES}" "$(tui::style bold bg_blue white)"
    wiz::draw_sidebar
    case "${SECTION}" in
        0) wiz::draw_locale ;;
        1) wiz::draw_encoding ;;
        2) wiz::draw_keyboard ;;
        3) wiz::draw_review ;;
    esac
    tui::statusbar "  ←→ steps   ↑↓ select   Enter choose/apply   o custom   q quit" "$(tui::style bg_black white)"
}

wiz::draw_input() {
    local -i w=56 h=5
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    tui::box "${by}" "${bx}" "${w}" "${h}" "${INPUT_LABEL}" "$(tui::style bold cyan)"
    tui::input $(( by + 2 )) $(( bx + 3 )) $(( w - 5 )) "${INPUT_VALUE}" "${INPUT_CURSOR}"
}

wiz::draw_picker() {
    local -i w=40 h=$(( ${#PICKER_VALS[@]} + 2 ))
    (( h > TUI_LINES - 4 )) && h=$(( TUI_LINES - 4 ))
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}" i
    tui::box "${by}" "${bx}" "${w}" "${h}" "${PICKER_FIELD}" "$(tui::style bold cyan)"
    local -i vis=$(( h - 2 )) offset=0 idx
    (( PICKER_SEL < offset )) && offset="${PICKER_SEL}"
    (( PICKER_SEL >= offset + vis )) && offset=$(( PICKER_SEL - vis + 1 ))
    for (( i = 0; i < vis; i++ )); do
        idx=$(( offset + i ))
        (( idx >= ${#PICKER_VALS[@]} )) && break
        if (( idx == PICKER_SEL )); then
            tui::put $(( by + 1 + i )) $(( bx + 2 )) "▸ ${PICKER_VALS[${idx}]}" "$(tui::style bold reverse)"
        else
            tui::put $(( by + 1 + i )) $(( bx + 2 )) "  ${PICKER_VALS[${idx}]}" ""
        fi
    done
    return 0
}

wiz::draw_confirm() {
    tui::confirm "Apply changes" "set ${BASE}.${ENCODING} and keyboard ${LAYOUT}?" "${CONFIRM_SEL}"
}

# Actions / Действия

wiz::open_input() {
    INPUT_LABEL="$1"; INPUT_TARGET="$2"; INPUT_VALUE=""; INPUT_CURSOR=0
    tui::modal::open input wiz::draw_input
}

wiz::open_picker() {
    PICKER_FIELD="${KBFIELDS[${SEL}],,}"
    wiz::picker_values
    PICKER_SEL=0
    tui::modal::open picker wiz::draw_picker
}

wiz::apply_input() {
    local -r v="${INPUT_VALUE}"
    case "${INPUT_TARGET}" in
        base)     BASE="${v}" ;;
        encoding) ENCODING="${v}" ;;
        layout)   LAYOUT="${v}" ;;
        model)    MODEL="${v}" ;;
        variant)  VARIANT="${v}" ;;
        options)  OPTIONS="${v}" ;;
    esac
}

wiz::apply() {
    tui::leave_alt
    tui::clear_screen
    printf 'Applying / Применяю…\n'
    system::locale::set "${BASE}.${ENCODING}" || true
    system::keyboard::layout "${LAYOUT}" || true
    system::keyboard::model "${MODEL}" || true
    [[ -n "${VARIANT}" ]] && system::keyboard::variant "${VARIANT}" || true
    [[ -n "${OPTIONS}" ]] && system::keyboard::options "${OPTIONS}" || true
    read -r -p "Press Enter to continue / Нажмите Enter…" || true
    tui::enter_alt
}

# Main loop / Главный цикл

main() {
    if ! system::utils::check_root; then
        printf '%s\n' "locale_wizard: root required / требуется root" >&2
        exit 1
    fi

    tui::init

    while true; do
        tui::handle_resize
        tui::buf::clear
        wiz::draw_frame
        tui::modal::draw_all
        tui::render
        tui::key_read

        local top
        top="$(tui::modal::top)"
        case "${top}" in
            input)
                case "${TUI_KEY}" in
                    ENTER) tui::modal::close; [[ -n "${INPUT_VALUE}" ]] && wiz::apply_input ;;
                    ESC)   tui::modal::close ;;
                    BACKSPACE)
                        (( INPUT_CURSOR > 0 )) || break
                        INPUT_VALUE="${INPUT_VALUE:0:${INPUT_CURSOR}-1}${INPUT_VALUE:${INPUT_CURSOR}}"
                        INPUT_CURSOR=$(( INPUT_CURSOR - 1 )) ;;
                    LEFT)  (( INPUT_CURSOR > 0 )) && INPUT_CURSOR=$(( INPUT_CURSOR - 1 )) ;;
                    RIGHT) (( INPUT_CURSOR < ${#INPUT_VALUE} )) && INPUT_CURSOR=$(( INPUT_CURSOR + 1 )) ;;
                    *)     INPUT_VALUE="${INPUT_VALUE:0:${INPUT_CURSOR}}${TUI_KEY}${INPUT_VALUE:${INPUT_CURSOR}}"
                           INPUT_CURSOR=$(( INPUT_CURSOR + 1 )) ;;
                esac
                ;;
            picker)
                case "${TUI_KEY}" in
                    ENTER)
                        tui::modal::close
                        local v="${PICKER_VALS[${PICKER_SEL}]}"
                        if [[ "${v}" == "Other…" ]]; then
                            wiz::open_input "Enter ${PICKER_FIELD}" "${PICKER_FIELD}"
                        elif [[ "${v}" == "(none)" ]]; then
                            wiz::set_kb ""
                        else
                            wiz::set_kb "${v}"
                        fi ;;
                    ESC)   tui::modal::close ;;
                    UP|k|K) (( PICKER_SEL > 0 )) && PICKER_SEL=$(( PICKER_SEL - 1 )) ;;
                    DOWN|j|J) (( PICKER_SEL < ${#PICKER_VALS[@]} - 1 )) && PICKER_SEL=$(( PICKER_SEL + 1 )) ;;
                esac
                ;;
            confirm)
                case "${TUI_KEY}" in
                    ENTER) tui::modal::close; (( CONFIRM_SEL == 0 )) && wiz::apply ;;
                    ESC)   tui::modal::close ;;
                    LEFT|RIGHT|TAB) CONFIRM_SEL=$(( 1 - CONFIRM_SEL )) ;;
                    y|Y) tui::modal::close; wiz::apply ;;
                    n|N) tui::modal::close ;;
                esac
                ;;
            *)
                case "${TUI_KEY}" in
                    q|Q|й|Й) break ;;
                    LEFT)  (( SECTION > 0 )) && { SECTION=$(( SECTION - 1 )); SEL=0; } ;;
                    RIGHT|TAB) (( SECTION < ${#SECTIONS[@]} - 1 )) && { SECTION=$(( SECTION + 1 )); SEL=0; } ;;
                    UP|k|K|ц|Ц)
                        if (( SECTION != 3 && SEL > 0 )); then SEL=$(( SEL - 1 )); fi ;;
                    DOWN|j|J|о|О)
                        if (( SECTION != 3 )); then
                            local -i m
                            m="$(wiz::sec_len)"
                            (( SEL < m - 1 )) && SEL=$(( SEL + 1 ))
                        fi ;;
                    o|O|щ|Щ)
                        case "${SECTION}" in
                            0) wiz::open_input "Locale base (e.g. en_US)" base ;;
                            1) wiz::open_input "Encoding (e.g. UTF-8)" encoding ;;
                            2) wiz::open_input "Layout" layout ;;
                        esac ;;
                    ENTER)
                        case "${SECTION}" in
                            0) local v; v="$(wiz::sel_value)"; [[ "${v}" == "Other…" ]] && wiz::open_input "Locale base (e.g. en_US)" base || BASE="${v}" ;;
                            1) local e; e="$(wiz::sel_value)"; ENCODING="${e}" ;;
                            2) wiz::open_picker ;;
                            3) CONFIRM_SEL=0; tui::modal::open confirm wiz::draw_confirm ;;
                        esac ;;
                esac
                ;;
        esac
    done

    tui::quit
}

if bs::is_main; then
    main "$@"
fi
