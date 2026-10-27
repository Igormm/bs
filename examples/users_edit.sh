#!/usr/bin/env bs
# shellcheck shell=bash
# examples/users_edit.sh — two-panel TUI for user and group management
# examples/users_edit.sh — двухпанельный TUI управления пользователями и группами
#
# Требует root. Слева — пользователи, справа — группы; Tab/←→ переключает панель.
# Портабельная версия: bs build examples/users_edit.sh --output bs-usersedit
# Requires root. Left — users, right — groups; Tab/←→ switches the panel.
# Portable version: bs build examples/users_edit.sh --output bs-usersedit
#
# Клавиши / Keys:
#   ←→ Tab      переключение панели / switch panel
#   ↑↓ j k      выбор / select
#   Пользователи: a добавить, e изменить (name/home/shell/gecos/group),
#                p пароль, l блокировать, u разблокировать, g добавить в группу,
#                d удалить, Enter инфо
#   Группы: a добавить, d удалить, Enter участники
#   q           выход / quit

load "lib/tui/tui"
load "lib/system/users"
load "lib/system/utils"

# ==========================================
# State / Состояние
# ==========================================

declare -a USERS=()
declare -a GROUPS=()
declare -a FIELDS=("name" "home" "shell" "gecos" "group")
declare -a INFO_LINES=()

declare -i PANEL=0          # 0=users, 1=groups
declare -i SEL_U=0
declare -i SEL_G=0

INPUT_LABEL=""
INPUT_VALUE=""
INPUT_CURSOR=0
INPUT_ACTION=""             # add_user | add_group | add_to_group | edit
FIELD_SEL=0
EDIT_FIELD=""
CONFIRM_TITLE=""
CONFIRM_TEXT=""
CONFIRM_SEL=0
CONFIRM_ACTION=""
INFO_TITLE=""

# ==========================================
# Data / Данные
# ==========================================

usersedit::reload() {
    local u shell
    USERS=()
    while IFS= read -r u; do
        [[ -z "${u}" ]] && continue
        shell="$(getent passwd "${u}" 2>/dev/null | cut -d: -f7)"
        case "${shell}" in
            *nologin|/bin/false) continue ;;
        esac
        USERS+=("${u}")
    done < <(system::users::list)
    GROUPS=()
    while IFS= read -r g; do
        [[ -z "${g}" ]] && continue
        GROUPS+=("${g}")
    done < <(system::users::group_list)
    (( SEL_U >= ${#USERS[@]} )) && SEL_U=$(( ${#USERS[@]} - 1 ))
    (( SEL_G >= ${#GROUPS[@]} )) && SEL_G=$(( ${#GROUPS[@]} - 1 ))
    (( SEL_U < 0 )) && SEL_U=0
    (( SEL_G < 0 )) && SEL_G=0
}

usersedit::cur_user() { printf '%s' "${USERS[${SEL_U}]:-}"; }
usersedit::cur_group() { printf '%s' "${GROUPS[${SEL_G}]:-}"; }

# ==========================================
# Draw / Отрисовка
# ==========================================

usersedit::draw_list() {
    local -r r="$1" c="$2" w="$3" h="$4" arr="$5" sel="$6"
    local -n items="${arr}"
    local -i total=${#items[@]} offset=0 i idx
    if (( total == 0 )); then
        tui::put "${r}" "${c}" "empty" "$(tui::style dim)"
        return 0
    fi
    (( sel < 0 )) && sel=0
    (( sel >= total )) && sel=$(( total - 1 ))
    (( sel < offset )) && offset="${sel}"
    (( sel >= offset + h )) && offset=$(( sel - h + 1 ))
    local -i active=$(( PANEL == 0 && arr == "USERS" ? 1 : (PANEL == 1 && arr == "GROUPS" ? 1 : 0) ))
    for (( i = 0; i < h; i++ )); do
        idx=$(( offset + i ))
        (( idx >= total )) && break
        local t="${items[${idx}]}"
        if (( idx == sel && active == 1 )); then
            tui::put $(( r + i )) "${c}" "▸ ${t:0:$(( w - 3 ))}" "$(tui::style bold reverse cyan)"
        else
            tui::put $(( r + i )) "${c}" "  ${t:0:$(( w - 3 ))}" ""
        fi
    done
}

usersedit::draw_panels() {
    local -i lw=$(( TUI_COLS / 2 ))
    local -i rw=$(( TUI_COLS - lw - 1 ))
    local -i h=$(( TUI_LINES - 3 ))
    local -i rx=$(( lw + 1 ))
    local st_u st_g
    st_u="$(tui::style bold cyan)"
    st_g="$(tui::style bold magenta)"
    (( PANEL == 1 )) && st_u="$(tui::style cyan)" || st_u="$(tui::style bold cyan)"
    (( PANEL == 0 )) && st_g="$(tui::style magenta)" || st_g="$(tui::style bold magenta)"
    tui::box 2 1 "${lw}" "${h}" "Users (${#USERS[@]})" "${st_u}"
    tui::box 2 "${rx}" "${rw}" "${h}" "Groups (${#GROUPS[@]})" "${st_g}"
    usersedit::draw_list 3 2 $(( lw - 2 )) $(( h - 2 )) "USERS" "${SEL_U}"
    usersedit::draw_list 3 $(( rx + 1 )) $(( rw - 2 )) $(( h - 2 )) "GROUPS" "${SEL_G}"
}

usersedit::draw_title() {
    tui::titlebar "  BS usersedit • $(date '+%H:%M:%S') • ${TUI_COLS}x${TUI_LINES}" "$(tui::style bold bg_blue white)"
}

usersedit::draw_status() {
    tui::statusbar "  ←→ panel  ↑↓ select  a add  e edit  p passwd  l lock  u unlock  g group  d delete  q quit" "$(tui::style bg_black white)"
}

usersedit::draw_input() {
    local -i w=56 h=5
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    tui::box "${by}" "${bx}" "${w}" "${h}" "${INPUT_LABEL}" "$(tui::style bold cyan)"
    tui::input $(( by + 2 )) $(( bx + 3 )) $(( w - 5 )) "${INPUT_VALUE}" "${INPUT_CURSOR}"
}

usersedit::draw_field() {
    local -i w=34 h=$(( ${#FIELDS[@]} + 2 ))
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}" i
    tui::box "${by}" "${bx}" "${w}" "${h}" "Edit field" "$(tui::style bold cyan)"
    for (( i = 0; i < ${#FIELDS[@]}; i++ )); do
        if (( i == FIELD_SEL )); then
            tui::put $(( by + 1 + i )) $(( bx + 2 )) "▸ ${FIELDS[${i}]}" "$(tui::style bold reverse)"
        else
            tui::put $(( by + 1 + i )) $(( bx + 2 )) "  ${FIELDS[${i}]}" ""
        fi
    done
}

usersedit::draw_confirm() {
    tui::confirm "${CONFIRM_TITLE}" "${CONFIRM_TEXT}" "${CONFIRM_SEL}"
}

usersedit::draw_info() {
    local -i w=60 h=$(( ${#INFO_LINES[@]} + 4 ))
    (( h < 5 )) && h=5
    tui::center "${w}" "${h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}" i
    tui::box "${by}" "${bx}" "${w}" "${h}" "${INFO_TITLE}" "$(tui::style bold green)"
    for (( i = 0; i < ${#INFO_LINES[@]}; i++ )); do
        tui::put $(( by + 2 + i )) $(( bx + 2 )) "${INFO_LINES[${i}]:0:$(( w - 4 ))}"
    done
}

usersedit::draw_frame() {
    usersedit::draw_title
    usersedit::draw_panels
    usersedit::draw_status
}

# ==========================================
# Modals / Модалки
# ==========================================

usersedit::open_input() {
    INPUT_LABEL="$1"; INPUT_ACTION="$2"; INPUT_VALUE=""; INPUT_CURSOR=0
    tui::modal::open input usersedit::draw_input
}

usersedit::open_field() {
    FIELD_SEL=0
    tui::modal::open field usersedit::draw_field
}

usersedit::open_confirm() {
    CONFIRM_TITLE="$1"; CONFIRM_TEXT="$2"; CONFIRM_ACTION="$3"; CONFIRM_SEL=0
    tui::modal::open confirm usersedit::draw_confirm
}

usersedit::open_info() {
    INFO_TITLE="$1"
    mapfile -t INFO_LINES < <("$2" "$3" 2>/dev/null)
    tui::modal::open info usersedit::draw_info
}

# ==========================================
# Actions / Действия
# ==========================================

usersedit::apply_input() {
    local -r v="${INPUT_VALUE}"
    case "${INPUT_ACTION}" in
        add_user)     system::users::create "${v}" ;;
        add_group)    system::users::group_create "${v}" ;;
        add_to_group) system::users::add_to_group "$(usersedit::cur_user)" "${v}" ;;
        edit)         system::users::modify "$(usersedit::cur_user)" "${EDIT_FIELD}" "${v}" ;;
    esac
    usersedit::reload
}

usersedit::apply_confirm() {
    local -r a="${CONFIRM_ACTION}"
    case "${a}" in
        delete_user)  system::users::delete "$(usersedit::cur_user)" ;;
        delete_group) system::users::group_delete "$(usersedit::cur_group)" ;;
    esac
    usersedit::reload
}

usersedit::set_password() {
    local -r u="$(usersedit::cur_user)"
    [[ -z "${u}" ]] && return 0
    tui::leave_alt
    tui::clear_screen
    system::users::set_password "${u}"
    read -r -p "Press Enter to continue / Нажмите Enter…"
    tui::enter_alt
}

# ==========================================
# Main loop / Главный цикл
# ==========================================

main() {
    if ! system::utils::check_root; then
        printf '%s\n' "usersedit: root required / требуется root" >&2
        exit 1
    fi

    usersedit::reload
    tui::init

    while true; do
        tui::handle_resize
        tui::buf::clear
        usersedit::draw_frame
        tui::modal::draw_all
        tui::render
        tui::key_read

        local top
        top="$(tui::modal::top)"
        case "${top}" in
            input)
                case "${TUI_KEY}" in
                    ENTER) tui::modal::close; [[ -n "${INPUT_VALUE}" ]] && usersedit::apply_input ;;
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
            field)
                case "${TUI_KEY}" in
                    ENTER) tui::modal::close; EDIT_FIELD="${FIELDS[${FIELD_SEL}]}"; usersedit::open_input "edit ${EDIT_FIELD}" edit ;;
                    ESC)   tui::modal::close ;;
                    UP|k|K) (( FIELD_SEL > 0 )) && FIELD_SEL=$(( FIELD_SEL - 1 )) ;;
                    DOWN|j|J) (( FIELD_SEL < ${#FIELDS[@]} - 1 )) && FIELD_SEL=$(( FIELD_SEL + 1 )) ;;
                esac
                ;;
            confirm)
                case "${TUI_KEY}" in
                    ENTER) tui::modal::close; (( CONFIRM_SEL == 0 )) && usersedit::apply_confirm ;;
                    ESC)   tui::modal::close ;;
                    LEFT|RIGHT|TAB) CONFIRM_SEL=$(( 1 - CONFIRM_SEL )) ;;
                    y|Y) tui::modal::close; usersedit::apply_confirm ;;
                    n|N) tui::modal::close ;;
                esac
                ;;
            info)
                tui::modal::close ;;
            *)
                case "${TUI_KEY}" in
                    q|Q|й|Й) break ;;
                    LEFT|TAB) PANEL=0 ;;
                    RIGHT)    PANEL=1 ;;
                    UP|k|K|ц|Ц)
                        if (( PANEL == 0 )); then (( SEL_U > 0 )) && SEL_U=$(( SEL_U - 1 )); else (( SEL_G > 0 )) && SEL_G=$(( SEL_G - 1 )); fi ;;
                    DOWN|j|J|о|О)
                        if (( PANEL == 0 )); then (( SEL_U < ${#USERS[@]} - 1 )) && SEL_U=$(( SEL_U + 1 )); else (( SEL_G < ${#GROUPS[@]} - 1 )) && SEL_G=$(( SEL_G + 1 )); fi ;;
                    a|A|ф|Ф)
                        if (( PANEL == 0 )); then usersedit::open_input "Add user" add_user; else usersedit::open_input "Add group" add_group; fi ;;
                    e|E|у|У)
                        (( PANEL == 0 )) && [[ -n "$(usersedit::cur_user)" ]] && usersedit::open_field ;;
                    p|P|з|З)
                        (( PANEL == 0 )) && usersedit::set_password ;;
                    l|L|д|Д)
                        (( PANEL == 0 )) && system::users::lock "$(usersedit::cur_user)" ;;
                    u|U|г|Г)
                        (( PANEL == 0 )) && system::users::unlock "$(usersedit::cur_user)" ;;
                    g|G|п|П)
                        (( PANEL == 0 )) && [[ -n "$(usersedit::cur_user)" ]] && usersedit::open_input "Add to group" add_to_group ;;
                    d|D|в|В)
                        if (( PANEL == 0 )); then
                            [[ -n "$(usersedit::cur_user)" ]] && usersedit::open_confirm "Delete user" "$(usersedit::cur_user)" delete_user
                        else
                            [[ -n "$(usersedit::cur_group)" ]] && usersedit::open_confirm "Delete group" "$(usersedit::cur_group)" delete_group
                        fi ;;
                    ENTER)
                        if (( PANEL == 0 )); then
                            [[ -n "$(usersedit::cur_user)" ]] && usersedit::open_info "User" system::users::info "$(usersedit::cur_user)"
                        else
                            [[ -n "$(usersedit::cur_group)" ]] && usersedit::open_info "Group" system::users::group_info "$(usersedit::cur_group)"
                        fi ;;
                esac
                ;;
        esac
    done

    tui::quit
}

# Запуск при исполнении или через `bs run` / Run when executed or via `bs run`
if bs::is_main; then
    main "$@"
fi
