#!/usr/bin/env bs
# shellcheck shell=bash
# examples/bootloader_wizard.sh — GRUB2 bootloader TUI wizard with safety
# examples/bootloader_wizard.sh — TUI-визард загрузчика GRUB2 с защитой
#
# Полноэкранный визард (lib/tui) настройки GRUB2 (/etc/default/grub) с защитой:
# перед изменением делается бэкап, значения валидируются, запись атомарная, а при
# сбое перегенерации конфиг автоматически откатывается на бэкап. Требует root.
# A full-screen wizard (lib/tui) for GRUB2 (/etc/default/grub) with safety: a
# backup is taken before editing, values are validated, the write is atomic, and
# on regeneration failure the config rolls back to the backup. Requires root.
#
# Клавиши / Keys:
#   ←→ Tab      секции / sections
#   ↑↓ j k      выбор / select
#   Enter       выбрать/применить / choose/apply
#   q           выход / quit

load "lib/tui/tui"
load "lib/system/bootloader"
load "lib/system/utils"

# Data / Данные

declare -a SECTIONS=("Timeout" "Default" "Cmdline" "Recovery" "Terminal" "Review")

declare -a DEFAULT_OPTIONS=("saved" "0 (first entry)" "1" "2" "Custom…")
declare -a RECOVERY_OPTIONS=("Keep recovery" "Disable recovery")
declare -a TERMINAL_OPTIONS=("console" "gfxterm" "serial")
declare -a CMDLINE_TOKENS=("quiet" "rhgb" "splash")

# State / Состояние

declare -i SECTION=0
declare -i SEL=0

TIMEOUT="5"
DEFAULT="saved"
CMDLINE=""
RECOVERY="false"
TERMINAL="console"

INPUT_LABEL=""
INPUT_VALUE=""
INPUT_CURSOR=0
INPUT_TARGET=""     # timeout | default | cmdline
CONFIRM_SEL=0

# Helpers / Помощники

wiz::load() {
    TIMEOUT="$(system::bootloader::grub_get GRUB_TIMEOUT 2>/dev/null || true)"
    DEFAULT="$(system::bootloader::grub_get GRUB_DEFAULT 2>/dev/null || true)"
    CMDLINE="$(system::bootloader::grub_get GRUB_CMDLINE_LINUX 2>/dev/null || true)"
    RECOVERY="$(system::bootloader::grub_get GRUB_DISABLE_RECOVERY 2>/dev/null || true)"
    TERMINAL="$(system::bootloader::grub_get GRUB_TERMINAL_OUTPUT 2>/dev/null || true)"
    [[ -z "${TIMEOUT}" ]] && TIMEOUT="5"
    [[ -z "${DEFAULT}" ]] && DEFAULT="saved"
    [[ -z "${RECOVERY}" ]] && RECOVERY="false"
    [[ -z "${TERMINAL}" ]] && TERMINAL="console"
}

wiz::sec_len() {
    case "${SECTION}" in
        0) printf '1' ;;
        1) printf '%s' "${#DEFAULT_OPTIONS[@]}" ;;
        2) printf '%s' "$(( ${#CMDLINE_TOKENS[@]} + 1 ))" ;;
        3) printf '%s' "${#RECOVERY_OPTIONS[@]}" ;;
        4) printf '%s' "${#TERMINAL_OPTIONS[@]}" ;;
        *) printf '1' ;;
    esac
    return 0
}

wiz::cmdline_has() {
    case " ${CMDLINE} " in *" ${1} "*) return 0 ;; esac
    return 1
}

wiz::cmdline_toggle() {
    local -r tok="${1}"
    if wiz::cmdline_has "${tok}"; then
        local t=" ${CMDLINE} "
        t="${t// ${tok} / }"
        CMDLINE="${t# }"; CMDLINE="${CMDLINE% }"
    else
        CMDLINE="${CMDLINE}${CMDLINE:+ }${tok}"
    fi
}

# Draw / Отрисовка

wiz::draw_sidebar() {
    local -i i
    tui::box 2 1 18 $(( ${#SECTIONS[@]} + 2 )) "Steps" "$(tui::style bold magenta)"
    for (( i = 0; i < ${#SECTIONS[@]}; i++ )); do
        if (( i == SECTION )); then
            tui::put $(( 3 + i )) 3 "▸ ${SECTIONS[${i}]}" "$(tui::style bold reverse white)"
        else
            tui::put $(( 3 + i )) 3 "  ${SECTIONS[${i}]}" ""
        fi
    done
}

wiz::list() {
    local -r title="$1"
    local -n vals="$2"
    local -i i total=${#vals[@]}
    tui::box 2 22 58 $(( TUI_LINES - 4 )) "${title}" "$(tui::style bold cyan)"
    local -i vis=$(( TUI_LINES - 6 )) offset=0 idx
    (( SEL < offset )) && offset="${SEL}"
    (( SEL >= offset + vis )) && offset=$(( SEL - vis + 1 ))
    for (( i = 0; i < vis; i++ )); do
        idx=$(( offset + i ))
        (( idx >= total )) && break
        local line="${vals[${idx}]}"
        if (( idx == SEL )); then
            tui::put $(( 3 + i )) 24 "▸ ${line:0:54}" "$(tui::style bold reverse cyan)"
        else
            tui::put $(( 3 + i )) 24 "  ${line:0:54}" ""
        fi
    done
    return 0
}

wiz::draw_timeout() {
    tui::box 2 22 58 $(( TUI_LINES - 4 )) "GRUB_TIMEOUT" "$(tui::style bold cyan)"
    local line="Current: ${TIMEOUT}  (Enter to edit)"
    if (( SEL == 0 )); then
        tui::put 4 24 "▸ ${line:0:54}" "$(tui::style bold reverse cyan)"
    else
        tui::put 4 24 "  ${line:0:54}" ""
    fi
    tui::put 6 24 "menu timeout in seconds / задержка меню в секундах" "$(tui::style dim)"
}

wiz::draw_default() {
    wiz::list "GRUB_DEFAULT" DEFAULT_OPTIONS
}

wiz::draw_cmdline() {
    tui::box 2 22 58 $(( TUI_LINES - 4 )) "GRUB_CMDLINE_LINUX" "$(tui::style bold cyan)"
    local -i i
    for (( i = 0; i < ${#CMDLINE_TOKENS[@]}; i++ )); do
        local mark="○"
        wiz::cmdline_has "${CMDLINE_TOKENS[${i}]}" && mark="●"
        local line="${mark} ${CMDLINE_TOKENS[${i}]}"
        if (( i == SEL )); then
            tui::put $(( 3 + i )) 24 "▸ ${line:0:54}" "$(tui::style bold reverse cyan)"
        else
            tui::put $(( 3 + i )) 24 "  ${line:0:54}" ""
        fi
    done
    local cline="Custom…   (current: ${CMDLINE:-<empty>})"
    if (( SEL == ${#CMDLINE_TOKENS[@]} )); then
        tui::put $(( 3 + ${#CMDLINE_TOKENS[@]} )) 24 "▸ ${cline:0:54}" "$(tui::style bold reverse cyan)"
    else
        tui::put $(( 3 + ${#CMDLINE_TOKENS[@]} )) 24 "  ${cline:0:54}" ""
    fi
}

wiz::draw_recovery() {
    local -i i
    tui::box 2 22 58 $(( TUI_LINES - 4 )) "Recovery entry" "$(tui::style bold cyan)"
    for (( i = 0; i < ${#RECOVERY_OPTIONS[@]}; i++ )); do
        local mark="○"
        if [[ "${RECOVERY}" == "false" && "${i}" == "0" ]] || [[ "${RECOVERY}" == "true" && "${i}" == "1" ]]; then mark="●"; fi
        local line="${mark} ${RECOVERY_OPTIONS[${i}]}"
        if (( i == SEL )); then
            tui::put $(( 3 + i )) 24 "▸ ${line:0:54}" "$(tui::style bold reverse cyan)"
        else
            tui::put $(( 3 + i )) 24 "  ${line:0:54}" ""
        fi
    done
}

wiz::draw_terminal() {
    wiz::list "GRUB_TERMINAL_OUTPUT" TERMINAL_OPTIONS
}

wiz::draw_review() {
    tui::box 2 22 58 $(( TUI_LINES - 4 )) "Review & apply" "$(tui::style bold green)"
    tui::put 4 24 "GRUB_TIMEOUT:          ${TIMEOUT}" "$(tui::style bold)"
    tui::put 5 24 "GRUB_DEFAULT:          ${DEFAULT}" "$(tui::style bold)"
    tui::put 6 24 "GRUB_CMDLINE_LINUX:    ${CMDLINE:-<empty>}" "$(tui::style bold)"
    tui::put 7 24 "GRUB_DISABLE_RECOVERY: ${RECOVERY}" "$(tui::style bold)"
    tui::put 8 24 "GRUB_TERMINAL_OUTPUT:  ${TERMINAL}" "$(tui::style bold)"
    tui::put 10 24 "Enter → backup, apply, regenerate" "$(tui::style dim)"
    tui::put 11 24 "on failure → auto-rollback to backup" "$(tui::style dim)"
}

wiz::draw_frame() {
    tui::titlebar "  BS Bootloader Wizard • ${TUI_COLS}x${TUI_LINES}" "$(tui::style bold bg_blue white)"
    wiz::draw_sidebar
    case "${SECTION}" in
        0) wiz::draw_timeout ;;
        1) wiz::draw_default ;;
        2) wiz::draw_cmdline ;;
        3) wiz::draw_recovery ;;
        4) wiz::draw_terminal ;;
        5) wiz::draw_review ;;
    esac
    tui::statusbar "  ←→ sections   ↑↓ select   Enter choose/apply   q quit" "$(tui::style bg_black white)"
}

wiz::draw_input() {
    local -i w=56 h=5
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    tui::box "${by}" "${bx}" "${w}" "${h}" "${INPUT_LABEL}" "$(tui::style bold cyan)"
    tui::input $(( by + 2 )) $(( bx + 3 )) $(( w - 5 )) "${INPUT_VALUE}" "${INPUT_CURSOR}"
}

wiz::draw_confirm() {
    tui::confirm "Apply bootloader" "backup, write and regenerate?" "${CONFIRM_SEL}"
}

# Actions / Действия

wiz::open_input() {
    INPUT_LABEL="$1"; INPUT_TARGET="$2"; INPUT_VALUE=""; INPUT_CURSOR=0
    tui::modal::open input wiz::draw_input
}

wiz::apply_input() {
    local -r v="${INPUT_VALUE}"
    case "${INPUT_TARGET}" in
        timeout) TIMEOUT="${v}" ;;
        default) DEFAULT="${v}" ;;
        cmdline) CMDLINE="${v}" ;;
    esac
}

wiz::apply() {
    tui::leave_alt
    tui::clear_screen
    printf 'Backing up / Бэкап…\n'
    local backup=""
    backup="$(system::bootloader::grub_backup 2>/dev/null || true)"
    printf 'Backup: %s\n' "${backup:-none}"

    system::bootloader::grub_set GRUB_TIMEOUT "${TIMEOUT}" || true
    system::bootloader::grub_set GRUB_DEFAULT "${DEFAULT}" || true
    system::bootloader::grub_set GRUB_CMDLINE_LINUX "${CMDLINE}" || true
    system::bootloader::grub_set GRUB_DISABLE_RECOVERY "${RECOVERY}" || true
    system::bootloader::grub_set GRUB_TERMINAL_OUTPUT "${TERMINAL}" || true

    printf 'Regenerating / Перегенерация…\n'
    if system::bootloader::regenerate; then
        printf 'OK. Backup kept: %s\n' "${backup:-none}"
    else
        if [[ -n "${backup}" ]]; then
            system::bootloader::grub_restore "${backup}" || true
            printf 'FAILED — rolled back to %s\n' "${backup}"
        else
            printf 'FAILED — no backup to roll back to\n'
        fi
    fi
    read -r -p "Press Enter to continue / Нажмите Enter…" || true
    tui::enter_alt
}

# Main loop / Главный цикл

main() {
    if ! system::utils::check_root; then
        printf '%s\n' "bootloader_wizard: root required / требуется root" >&2
        exit 1
    fi

    wiz::load
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
                        if (( SECTION != 0 && SECTION != 5 && SEL > 0 )); then SEL=$(( SEL - 1 )); fi ;;
                    DOWN|j|J|о|О)
                        if (( SECTION != 0 && SECTION != 5 )); then
                            local -i m
                            m="$(wiz::sec_len)"
                            (( SEL < m - 1 )) && SEL=$(( SEL + 1 ))
                        fi ;;
                    ENTER)
                        case "${SECTION}" in
                            0) wiz::open_input "GRUB_TIMEOUT (seconds)" timeout ;;
                            1) if [[ "${DEFAULT_OPTIONS[${SEL}]}" == "Custom…" ]]; then
                                   wiz::open_input "GRUB_DEFAULT" default
                               elif [[ "${SEL}" == "0" ]]; then DEFAULT="saved"
                               else DEFAULT="${DEFAULT_OPTIONS[${SEL}]%% *}"
                               fi ;;
                            2) if (( SEL < ${#CMDLINE_TOKENS[@]} )); then
                                   wiz::cmdline_toggle "${CMDLINE_TOKENS[${SEL}]}"
                               else
                                   wiz::open_input "GRUB_CMDLINE_LINUX" cmdline
                               fi ;;
                            3) if (( SEL == 0 )); then RECOVERY="false"; else RECOVERY="true"; fi ;;
                            4) TERMINAL="${TERMINAL_OPTIONS[${SEL}]}" ;;
                            5) CONFIRM_SEL=0; tui::modal::open confirm wiz::draw_confirm ;;
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
