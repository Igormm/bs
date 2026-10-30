#!/usr/bin/env bs
# shellcheck shell=bash
# examples/ntp_wizard.sh — NTP configuration TUI wizard
# examples/ntp_wizard.sh — TUI-визард настройки NTP
#
# Полноэкранный визард (lib/tui): включить/выключить синхронизацию NTP, выбрать
# пул серверов (или свои), просмотр и применение. Требует root (timedatectl и запись
# в /etc/chrony.conf|ntp.conf|timesyncd.conf). Портабельная версия:
#   bs build examples/ntp_wizard.sh --output bs-ntp-wizard
# A full-screen wizard (lib/tui): enable/disable NTP, pick a server pool (or your
# own), review and apply. Requires root (timedatectl and /etc/chrony.conf|ntp.conf|
# timesyncd.conf). Portable build:
#   bs build examples/ntp_wizard.sh --output bs-ntp-wizard
#
# Клавиши / Keys:
#   ←→ Tab      переключение секции / switch section
#   ↑↓ j k      выбор / select
#   Enter       выбрать/применить / choose/apply
#   o           свои серверы (Custom) / custom servers
#   q           выход / quit

load "lib/tui/tui"
load "lib/system/time"
load "lib/system/utils"

# Data / Данные

declare -a SECTIONS=("NTP" "Servers" "Review")
declare -a NTP_OPTIONS=("Enable NTP synchronization" "Disable NTP synchronization")

declare -a POOLS=(
  "pool.ntp.org — global"
  "0-3.pool.ntp.org — worldwide"
  "ru.pool.ntp.org — Russia"
  "europe.pool.ntp.org — Europe"
  "asia.pool.ntp.org — Asia"
  "Cloudflare + Google"
  "Custom…"
)
declare -a POOL_SERVERS=(
  "pool.ntp.org"
  "0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org"
  "ru.pool.ntp.org"
  "europe.pool.ntp.org"
  "asia.pool.ntp.org"
  "time.cloudflare.com time.google.com"
  ""
)

# State / Состояние

declare -i SECTION=0
declare -i SEL=0
NTP_ENABLE="true"
declare -a SERVERS=( "pool.ntp.org" )

INPUT_LABEL=""
INPUT_VALUE=""
INPUT_CURSOR=0
CONFIRM_SEL=0

# Helpers / Помощники

wiz::sec_len() {
    case "${SECTION}" in
        0) printf '%s' "${#NTP_OPTIONS[@]}" ;;
        1) printf '%s' "${#POOLS[@]}" ;;
        *) printf '1' ;;
    esac
    return 0
}

wiz::split_servers() {
    SERVERS=()
    local -a tmp=()
    IFS=' ' read -ra tmp <<< "${1}"
    local s
    for s in "${tmp[@]}"; do
        [[ -n "${s}" ]] && SERVERS+=("${s}")
    done
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

wiz::draw_ntp() {
    tui::box 2 23 56 $(( TUI_LINES - 4 )) "NTP synchronization" "$(tui::style bold cyan)"
    local -i i
    for (( i = 0; i < ${#NTP_OPTIONS[@]}; i++ )); do
        local mark="○"
        if [[ "${NTP_ENABLE}" == "true" && "${i}" == "0" ]] || [[ "${NTP_ENABLE}" == "false" && "${i}" == "1" ]]; then
            mark="●"
        fi
        local line="${mark} ${NTP_OPTIONS[${i}]}"
        if (( i == SEL )); then
            tui::put $(( 3 + i )) 25 "▸ ${line:0:52}" "$(tui::style bold reverse cyan)"
        else
            tui::put $(( 3 + i )) 25 "  ${line:0:52}" ""
        fi
    done
}

wiz::draw_servers() {
    tui::box 2 23 56 $(( TUI_LINES - 4 )) "NTP servers" "$(tui::style bold cyan)"
    local -i i
    local -i total=${#POOLS[@]}
    local -i vis=$(( TUI_LINES - 6 )) offset=0 idx
    (( SEL < offset )) && offset="${SEL}"
    (( SEL >= offset + vis )) && offset=$(( SEL - vis + 1 ))
    for (( i = 0; i < vis; i++ )); do
        idx=$(( offset + i ))
        (( idx >= total )) && break
        local line="${POOLS[${idx}]}"
        if (( idx == SEL )); then
            tui::put $(( 3 + i )) 25 "▸ ${line:0:52}" "$(tui::style bold reverse cyan)"
        else
            tui::put $(( 3 + i )) 25 "  ${line:0:52}" ""
        fi
    done
    return 0
}

wiz::draw_review() {
    local state="disabled"
    [[ "${NTP_ENABLE}" == "true" ]] && state="enabled"
    tui::box 2 23 56 $(( TUI_LINES - 4 )) "Review & apply" "$(tui::style bold green)"
    tui::put 4 25 "NTP:      ${state}" "$(tui::style bold)"
    tui::put 5 25 "Servers:  ${SERVERS[*]}" "$(tui::style bold)"
    tui::put 7 25 "Press Enter to apply / Enter — применить" "$(tui::style dim)"
    tui::put 8 25 "timedatectl set-ntp ${NTP_ENABLE}" "$(tui::style dim)"
    tui::put 9 25 "ntp servers -> ${SERVERS[*]}" "$(tui::style dim)"
}

wiz::draw_frame() {
    tui::titlebar "  BS NTP Wizard • ${TUI_COLS}x${TUI_LINES}" "$(tui::style bold bg_blue white)"
    wiz::draw_sidebar
    case "${SECTION}" in
        0) wiz::draw_ntp ;;
        1) wiz::draw_servers ;;
        2) wiz::draw_review ;;
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

wiz::draw_confirm() {
    tui::confirm "Apply NTP" "set NTP ${NTP_ENABLE} and servers ${SERVERS[*]}?" "${CONFIRM_SEL}"
}

# Actions / Действия

wiz::open_input() {
    INPUT_LABEL="$1"; INPUT_VALUE=""; INPUT_CURSOR=0
    tui::modal::open input wiz::draw_input
}

wiz::apply() {
    tui::leave_alt
    tui::clear_screen
    printf 'Applying / Применяю…\n'
    system::time::ntp "${NTP_ENABLE}" || true
    system::time::ntp_servers "${SERVERS[@]}" || true
    read -r -p "Press Enter to continue / Нажмите Enter…" || true
    tui::enter_alt
}

# Main loop / Главный цикл

main() {
    if ! system::utils::check_root; then
        printf '%s\n' "ntp_wizard: root required / требуется root" >&2
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
                    ENTER) tui::modal::close; [[ -n "${INPUT_VALUE}" ]] && wiz::split_servers "${INPUT_VALUE}" ;;
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
                        if (( SECTION != 2 && SEL > 0 )); then SEL=$(( SEL - 1 )); fi ;;
                    DOWN|j|J|о|О)
                        if (( SECTION != 2 )); then
                            local -i m
                            m="$(wiz::sec_len)"
                            (( SEL < m - 1 )) && SEL=$(( SEL + 1 ))
                        fi ;;
                    o|O|щ|Щ)
                        if (( SECTION == 1 )); then wiz::open_input "NTP servers (space-separated)"; fi ;;
                    ENTER)
                        case "${SECTION}" in
                            0) if (( SEL == 0 )); then NTP_ENABLE="true"; else NTP_ENABLE="false"; fi ;;
                            1) if [[ "${POOLS[${SEL}]}" == "Custom…" ]]; then
                                   wiz::open_input "NTP servers (space-separated)"
                               else
                                   wiz::split_servers "${POOL_SERVERS[${SEL}]}"
                               fi ;;
                            2) CONFIRM_SEL=0; tui::modal::open confirm wiz::draw_confirm ;;
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
