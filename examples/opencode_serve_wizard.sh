#!/usr/bin/env bs
# shellcheck shell=bash
# examples/opencode_serve_wizard.sh — interactive wizard for the opencode server
# examples/opencode_serve_wizard.sh — интерактивный визард для opencode-сервера
#
# Centered full-screen wizard built on the BS TUI library (lib/tui/tui):
# chooses the bind IP (auto-detect / interface / explicit), port and
# password, then launches `opencode serve`. All elements are centered,
# every key is handled safely (unknown keys are ignored, q cancels; a
# stray ESC — e.g. a fast arrow split by latency — is a safe no-op),
# the terminal is restored on any exit, resizes are handled per frame.
# Центрированный полноэкранный визард на TUI-библиотеке BS (lib/tui/tui):
# выбор IP (авто / интерфейс / явный), порта и пароля, затем запуск
# `opencode serve`. Все элементы в центре экрана, любая клавиша
# обрабатывается безопасно (неизвестные игнорируются, отмена — q;
# одиночный ESC — например, стрелка, разбитая задержкой, — безопасный no-op),
# терминал восстанавливается при любом выходе, resize обрабатывается
# каждый кадр.
#
# Run / Запуск:
#   bs run examples/opencode_serve_wizard.sh
#   ./examples/opencode_serve_wizard.sh
#
# Keys / Клавиши:
#   ↑/↓ — выбор · Enter — OK · q — отмена/выход

load "core/utils"
load "lib/tui/tui"
load "lib/system/utils"

# ==========================================
# State / Состояние
# ==========================================

declare -g WZ_IP=""            # итоговый IP / final IP
declare -g WZ_HOST="0.0.0.0"   # --hostname для opencode / --hostname for opencode
declare -g WZ_PORT="${PORT:-4096}"
declare -g WZ_PASS=""          # пароль / password (пусто = нет / empty = none)
declare -g WZ_PASS_MODE="none" # generated | entered | env | none
declare -g WZ_AUTO_IP=""       # автоопределённый IP / auto-detected IP
declare -g WZ_IFACE=""         # выбранный интерфейс / chosen interface
declare -g WZ_SOURCE="auto"    # auto | iface | ip

# ==========================================
# Input helpers / Помощники ввода
# ==========================================

# @private Key read with UTF-8 support: tui::key_read + continuation bytes.
# @private Чтение клавиши с поддержкой UTF-8: tui::key_read + байты продолжения.
# @stdout key name / символ клавиши (TUI_KEY или UTF-8 символ)
wz::read_char() {
    tui::key_read
    local k="${TUI_KEY}"
    if (( ${#k} == 1 )); then
        local -i ord
        printf -v ord '%d' "'${k}"
        if (( ord >= 0xC0 && ord <= 0xF7 )); then
            local -i extra=1
            (( ord >= 0xE0 )) && extra=2
            (( ord >= 0xF0 )) && extra=3
            local piece
            local -i j
            for (( j = 0; j < extra; j++ )); do
                IFS= read -r -s -n1 -t 0.05 piece || break
                k+="${piece}"
            done
        fi
    fi
    printf '%s' "${k}"
}

# ==========================================
# Widgets / Виджеты (все центрированы / all centered)
# ==========================================

# @description Centered single-choice menu (arrows + Enter + q).
# @description Центрированное меню выбора (стрелки + Enter + q).
# @param $1 Output variable: selected index (0-based), "99" = cancelled
# @param $2 Title / Заголовок
# @param $@ Items / Пункты
wz::menu() {
    local -n wz_out="${1:?output variable required}"
    local -r wz_title="${2:?title required}"
    shift 2
    local -a wz_items=("$@")
    local -i wz_sel=0
    local -i wz_h=$(( ${#wz_items[@]} + 4 ))
    (( wz_h > TUI_LINES - 4 )) && wz_h=$(( TUI_LINES - 4 ))
    (( wz_h < 6 )) && wz_h=6
    local -r wz_w=64

    while true; do
        tui::buf::clear
        tui::center "${wz_w}" "${wz_h}"
        local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
        local st
        st="$(tui::style bold cyan)"
        tui::box "${by}" "${bx}" "${wz_w}" "${wz_h}" "${wz_title}" "${st}"
        tui::list $(( by + 2 )) $(( bx + 2 )) $(( wz_w - 4 )) $(( wz_h - 3 )) wz_items "${wz_sel}"
        tui::statusbar "  ↑/↓ — выбор · Enter — OK · q — отмена / cancel" "$(tui::style bg_black white)"
        tui::render

        tui::key_read
        case "${TUI_KEY}" in
            UP)   (( wz_sel > 0 )) && wz_sel=$(( wz_sel - 1 )) ;;
            DOWN) (( wz_sel < ${#wz_items[@]} - 1 )) && wz_sel=$(( wz_sel + 1 )) ;;
            ENTER) wz_out="${wz_sel}"; return 0 ;;
            q|Q) wz_out="99"; return 0 ;;
            # ESC не отменяет: быстрая стрелка может прийти как одиночный ESC
            # ESC does not cancel: a fast arrow can arrive as a lone ESC
            ESC) : ;;
        esac
    done
}

# @description Centered text input with a default value.
# @description Центрированный текстовый ввод со значением по умолчанию.
# @param $1 Output variable ("q" = cancelled) / Выходная переменная
# @param $2 Title / Заголовок
# @param $3 Default / Значение по умолчанию
wz::input() {
    local -n wz_out="${1:?output variable required}"
    local -r wz_title="${2:?title required}"
    local wz_value="${3:-}"
    local -i wz_cur=${#wz_value}
    local -r wz_w=64
    local -r wz_h=7

    while true; do
        tui::buf::clear
        tui::center "${wz_w}" "${wz_h}"
        local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
        local st
        st="$(tui::style bold yellow)"
        tui::box "${by}" "${bx}" "${wz_w}" "${wz_h}" "${wz_title}" "${st}"
        tui::put $(( by + 2 )) $(( bx + 2 )) "▸" "$(tui::style bold)"
        tui::input $(( by + 2 )) $(( bx + 4 )) $(( wz_w - 8 )) "${wz_value}" "${wz_cur}"
        tui::put $(( by + 4 )) $(( bx + 2 )) "Enter — OK · q — отмена / cancel" "$(tui::style dim)"
        tui::render

        local key
        key="$(wz::read_char)"
        case "${key}" in
            ENTER) wz_out="${wz_value}"; return 0 ;;
            q|Q) wz_out="q"; return 0 ;;
            ESC) : ;;
            BACKSPACE)
                (( wz_cur > 0 )) || continue
                wz_value="${wz_value:0:$(( wz_cur - 1 ))}${wz_value:${wz_cur}}"
                wz_cur=$(( wz_cur - 1 ))
                ;;
            LEFT)  (( wz_cur > 0 )) && wz_cur=$(( wz_cur - 1 )) ;;
            RIGHT) (( wz_cur < ${#wz_value} )) && wz_cur=$(( wz_cur + 1 )) ;;
            TAB|UP|DOWN|HOME|END|INSERT|DELETE|PGUP|PGDN|BTAB|MOUSE|UNKNOWN|SOME|F1|F2|F3|F4|F5|F6|F7|F8|F9|F10|F11|F12)
                : ;; # безопасно игнорируем / safely ignored
            *)
                # только печатный символ: без ALT+/CTRL+/SHIFT+-комбинаций
                # printable char only: no ALT+/CTRL+/SHIFT+ combos
                if [[ "${key}" =~ ^[[:print:]]+$ ]] && [[ "${key}" != *[[:space:]]* ]] && [[ "${key}" != *+* ]]; then
                    wz_value="${wz_value:0:${wz_cur}}${key}${wz_value:${wz_cur}}"
                    wz_cur=$(( wz_cur + 1 ))
                fi
                ;;
        esac
    done
}

# @description Centered hidden password input.
# @description Центрированный скрытый ввод пароля.
# @param $1 Output variable ("q" = cancelled) / Выходная переменная
# @param $2 Title / Заголовок
wz::pass_input() {
    local -n wz_out="${1:?output variable required}"
    local -r wz_title="${2:?title required}"
    local wz_value=""
    local -i wz_cur=0
    local -r wz_w=64
    local -r wz_h=7

    while true; do
        tui::buf::clear
        tui::center "${wz_w}" "${wz_h}"
        local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
        local st
        st="$(tui::style bold yellow)"
        tui::box "${by}" "${bx}" "${wz_w}" "${wz_h}" "${wz_title}" "${st}"
        tui::put $(( by + 2 )) $(( bx + 2 )) "▸" "$(tui::style bold)"
        local masked="" 
        local -i i
        for (( i = 0; i < ${#wz_value}; i++ )); do masked+="●"; done
        tui::input $(( by + 2 )) $(( bx + 4 )) $(( wz_w - 8 )) "${masked}" "${wz_cur}"
        tui::put $(( by + 4 )) $(( bx + 2 )) "ввод скрыт / hidden · Enter — OK · q — отмена / cancel" "$(tui::style dim)"
        tui::render

        local key
        key="$(wz::read_char)"
        case "${key}" in
            ENTER) wz_out="${wz_value}"; return 0 ;;
            q|Q) wz_out="q"; return 0 ;;
            ESC) : ;;
            BACKSPACE)
                (( wz_cur > 0 )) || continue
                wz_value="${wz_value:0:$(( wz_cur - 1 ))}${wz_value:${wz_cur}}"
                wz_cur=$(( wz_cur - 1 ))
                ;;
            LEFT)  (( wz_cur > 0 )) && wz_cur=$(( wz_cur - 1 )) ;;
            RIGHT) (( wz_cur < ${#wz_value} )) && wz_cur=$(( wz_cur + 1 )) ;;
            TAB|UP|DOWN|HOME|END|INSERT|DELETE|PGUP|PGDN|BTAB|MOUSE|UNKNOWN|SOME|F1|F2|F3|F4|F5|F6|F7|F8|F9|F10|F11|F12)
                : ;; # безопасно игнорируем / safely ignored
            *)
                # только печатный символ: без ALT+/CTRL+/SHIFT+-комбинаций
                # printable char only: no ALT+/CTRL+/SHIFT+ combos
                if [[ "${key}" =~ ^[[:print:]]+$ ]] && [[ "${key}" != *[[:space:]]* ]] && [[ "${key}" != *+* ]]; then
                    wz_value="${wz_value:0:${wz_cur}}${key}${wz_value:${wz_cur}}"
                    wz_cur=$(( wz_cur + 1 ))
                fi
                ;;
        esac
    done
}

# @description Centered error frame; waits for any key.
# @description Центрированная рамка ошибки; ждёт любую клавишу.
# @param $1 Message / Сообщение
wz::error() {
    local -r wz_msg="$1"
    local -r wz_w=64
    local -r wz_h=6
    tui::buf::clear
    tui::center "${wz_w}" "${wz_h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local st
    st="$(tui::style bold red)"
    tui::box "${by}" "${bx}" "${wz_w}" "${wz_h}" "Ошибка / Error" "${st}"
    tui::put $(( by + 2 )) $(( bx + 2 )) "${wz_msg:0:$(( wz_w - 4 ))}"
    tui::put $(( by + 3 )) $(( bx + 2 )) "Enter — продолжить / continue" "$(tui::style dim)"
    tui::render
    tui::key_read
}

# ==========================================
# Steps / Шаги
# ==========================================

# @private IPv4 format validation / Проверка формата IPv4
# @param $1 Value to check / Проверяемое значение
# @return 0 valid, 1 invalid / 0 корректно, 1 нет
wz::validate_ipv4() {
    local -r value="${1:-}"
    local -a octets=()
    local octet
    [[ "${value}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    local IFS='.'
    read -ra octets <<< "${value}"
    for octet in "${octets[@]}"; do
        (( 10#${octet} <= 255 )) || return 1
    done
    return 0
}

# @private Generate a password / Сгенерировать пароль
# @stdout password / пароль
wz::gen_pass() {
    if is::command openssl; then
        openssl rand -base64 18 | tr '+/' '_-'
    else
        tr -dc 'A-Za-z0-9_-' < /dev/urandom | head -c 18
        printf '\n'
    fi
}

# @private Explicit IP step (validates, retries) / Шаг «явный IP» (с проверкой).
# @return 0 ok, 1 cancelled / 0 успех, 1 отмена
wz::step_ip() {
    local value
    while true; do
        wz::input value "IP сервера / Server IP  (например / e.g. 192.168.1.50)" ""
        [[ "${value}" == "q" ]] && return 1
        if wz::validate_ipv4 "${value}"; then
            WZ_IP="${value}"
            WZ_SOURCE="ip"
            return 0
        fi
        wz::error "Неверный IP / Invalid IP: ${value}"
    done
}

# @private Interface step (lists interfaces with IPv4) / Шаг «интерфейс».
# @return 0 ok, 1 cancelled / 0 успех, 1 отмена
wz::step_iface() {
    local -a wz_names=() wz_items=()
    local iface ip
    while IFS= read -r iface; do
        ip="$(utils::attempt system::utils::get_ip_address_for_interface "${iface}")"
        wz_names+=("${iface}")
        if is::not_empty "${ip}"; then
            wz_items+=("${iface}  →  ${ip}")
        else
            wz_items+=("${iface}  (без IPv4 / no IPv4)")
        fi
    done < <(ip -4 -o addr show 2>/dev/null | awk '$2 != "lo" {print $2}' | sort -u)

    if (( ${#wz_names[@]} == 0 )); then
        wz::error "Нет интерфейсов с IPv4 / No interfaces with IPv4"
        return 1
    fi

    local pick
    wz::menu pick "Сетевой интерфейс / Network interface" "${wz_items[@]}"
    [[ "${pick}" == "99" ]] && return 1
    WZ_IFACE="${wz_names[${pick}]}"
    WZ_IP="$(utils::attempt system::utils::get_ip_address_for_interface "${WZ_IFACE}")"
    WZ_SOURCE="iface"
    return 0
}

# @private Port step (validates 1-65535, retries) / Шаг «порт» (с проверкой).
# @return 0 ok, 1 cancelled / 0 успех, 1 отмена
wz::step_port() {
    local value
    while true; do
        wz::input value "Порт сервера / Server port" "${WZ_PORT}"
        [[ "${value}" == "q" ]] && return 1
        if [[ "${value}" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 65535 )); then
            WZ_PORT="${value}"
            return 0
        fi
        wz::error "Порт должен быть числом 1-65535 / Port must be 1-65535: ${value}"
    done
}

# @private Password step (generate / enter / none; env wins).
# @private Шаг «пароль» (сгенерировать / ввести / без пароля; env важнее).
# @return 0 ok, 1 cancelled / 0 успех, 1 отмена
wz::step_pass() {
    if is::not_empty "${OPENCODE_SERVER_PASSWORD:-}"; then
        WZ_PASS="${OPENCODE_SERVER_PASSWORD}"
        WZ_PASS_MODE="env"
        return 0
    fi

    local pick pass
    wz::menu pick "Пароль сервера / Server password" \
        "Сгенерировать / Generate" \
        "Ввести свой / Enter my own" \
        "Без пароля / No password"
    [[ "${pick}" == "99" ]] && return 1
    case "${pick}" in
        0)
            WZ_PASS="$(wz::gen_pass)"
            WZ_PASS_MODE="generated"
            ;;
        1)
            wz::pass_input pass "Пароль сервера / Server password"
            [[ "${pass}" == "q" ]] && return 1
            WZ_PASS="${pass}"
            if is::empty "${WZ_PASS}"; then
                WZ_PASS_MODE="none"
            else
                WZ_PASS_MODE="entered"
            fi
            ;;
        2)
            WZ_PASS=""
            WZ_PASS_MODE="none"
            ;;
    esac
    return 0
}

# @private Centered summary + Yes/No / Центрированная сводка + Да/Нет.
# @param $1 selected choice (0 = yes, 1 = no) / выбранный ответ
wz::draw_summary() {
    local -r sel="$1"
    local -r wz_w=68
    local -r wz_h=12
    tui::center "${wz_w}" "${wz_h}"
    local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
    local st
    st="$(tui::style bold green)"
    tui::box "${by}" "${bx}" "${wz_w}" "${wz_h}" "Сводка / Summary" "${st}"

    local mode_desc
    case "${WZ_SOURCE}" in
        auto)  mode_desc="автоопределение / auto-detect" ;;
        iface) mode_desc="интерфейс ${WZ_IFACE} / interface ${WZ_IFACE}" ;;
        ip)    mode_desc="указанный IP / explicit IP" ;;
    esac
    local pass_desc
    case "${WZ_PASS_MODE}" in
        generated) pass_desc="сгенерирован / generated" ;;
        entered)   pass_desc="введён / entered" ;;
        env)       pass_desc="из окружения / from env" ;;
        none)      pass_desc="нет / none (НЕБЕЗОПАСНО / UNSECURED)" ;;
    esac

    local -i row=$(( by + 2 ))
    tui::put "$(( row++ ))" $(( bx + 2 )) "IP:        ${WZ_HOST}"
    tui::put "$(( row++ ))" $(( bx + 2 )) "Источник:  ${mode_desc}"
    tui::put "$(( row++ ))" $(( bx + 2 )) "Порт:      ${WZ_PORT}"
    tui::put "$(( row++ ))" $(( bx + 2 )) "Пароль:    ${pass_desc}"
    tui::put "$(( row++ ))" $(( bx + 2 )) "Подключение / Connect:"
    tui::put "$(( row++ ))" $(( bx + 4 )) "opencode attach http://${WZ_HOST}:${WZ_PORT} -u opencode -p '...'"
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        tui::put "$(( row++ ))" $(( bx + 2 )) "Файрвол:   sudo firewall-cmd --add-port=${WZ_PORT}/tcp --permanent &&"
        tui::put "$(( row++ ))" $(( bx + 10 )) "sudo firewall-cmd --reload"
    fi

    local yes_st no_st
    if (( sel == 0 )); then
        yes_st="$(tui::style reverse green)"
        no_st=""
    else
        yes_st=""
        no_st="$(tui::style reverse red)"
    fi
    tui::put $(( by + wz_h - 2 )) $(( bx + 2 )) "Запустить? / Start?" "$(tui::style bold)"
    tui::put $(( by + wz_h - 2 )) $(( bx + 20 )) "[ Да / Yes ]" "${yes_st}"
    tui::put $(( by + wz_h - 2 )) $(( bx + 36 )) "[ Нет / No ]" "${no_st}"
}

# @private Confirm step / Шаг подтверждения.
# @return 0 yes, 1 no / 0 да, 1 нет
wz::step_confirm() {
    local -i sel=0
    while true; do
        tui::buf::clear
        wz::draw_summary "${sel}"
        tui::render
        tui::key_read
        case "${TUI_KEY}" in
            ENTER) return "${sel}" ;;
            y|Y)   return 0 ;;
            n|N|q|Q|ESC) return 1 ;;
            LEFT|RIGHT|TAB) sel=$(( 1 - sel )) ;;
        esac
    done
}

# ==========================================
# Main / Главная
# ==========================================

main() {
    tui::init
    tui::buf::clear

    # ---- opencode installed? / opencode установлен?
    if ! is::command opencode; then
        wz::error "opencode не установлен / not installed — https://opencode.ai"
        tui::quit
        exit 1
    fi

    # ---- welcome / приветствие
    local -r wz_w=64
    local -r wz_h=8
    while true; do
        tui::buf::clear
        tui::center "${wz_w}" "${wz_h}"
        local -i bx="${TUI_CENTER_X}" by="${TUI_CENTER_Y}"
        local st
        st="$(tui::style bold cyan)"
        tui::box "${by}" "${bx}" "${wz_w}" "${wz_h}" "opencode server — визард / wizard" "${st}"
        tui::put $(( by + 2 )) $(( bx + 2 )) "Запуск сервера opencode с basic auth." "$(tui::style dim)"
        tui::put $(( by + 3 )) $(( bx + 2 )) "Шаги: IP → порт → пароль → запуск." "$(tui::style dim)"
        tui::put $(( by + 3 )) $(( bx + 28 )) "Steps: IP → port → password → run." "$(tui::style dim)"
        tui::put $(( by + 5 )) $(( bx + 2 )) "Enter — начать / to start · q — выход / quit" "$(tui::style bold)"
        tui::render
        tui::key_read
        case "${TUI_KEY}" in
            ENTER|y|Y) break ;;
            q|Q) tui::quit; exit 0 ;;
            # одиночный ESC не выходит — стрелка может прийти как ESC
            # a lone ESC does not quit — an arrow can arrive as ESC
            ESC) : ;;
        esac
    done

    # ---- авто-IP для подсказки / auto IP for the hint
    WZ_AUTO_IP="$(utils::attempt system::utils::get_ip_address)"

    # ---- шаг 1: источник IP / IP source
    local pick
    while true; do
        if is::empty "${WZ_AUTO_IP}"; then
            wz::menu pick "Откуда брать IP / IP source" \
                "Автоопределение / Auto-detect" \
                "Сетевой интерфейс / Network interface" \
                "Указанный IP / Explicit IP"
        else
            wz::menu pick "Откуда брать IP / IP source" \
                "Автоопределение / Auto-detect (${WZ_AUTO_IP})" \
                "Сетевой интерфейс / Network interface" \
                "Указанный IP / Explicit IP"
        fi
        [[ "${pick}" == "99" ]] && { tui::quit; exit 0; }
        case "${pick}" in
            0)
                WZ_IP="${WZ_AUTO_IP}"
                WZ_SOURCE="auto"
                break
                ;;
            1)
                wz::step_iface && break
                # нет интерфейсов или отмена — меню заново / re-ask the menu
                ;;
            2)
                wz::step_ip && break
                ;;
        esac
    done

    # ---- шаг 2: порт / port
    wz::step_port || { tui::quit; exit 0; }

    # ---- шаг 3: пароль / password
    wz::step_pass || { tui::quit; exit 0; }

    # ---- итоговый host / final hostname
    if is::empty "${WZ_IP}"; then
        WZ_HOST="0.0.0.0"
    else
        WZ_HOST="${WZ_IP}"
    fi

    # ---- сводка / summary
    if ! wz::step_confirm; then
        tui::quit
        exit 0
    fi

    # ---- запуск / launch
    tui::quit
    printf 'opencode server: http://%s:%s\n' "${WZ_HOST}" "${WZ_PORT}"
    if is::empty "${WZ_PASS}"; then
        printf 'connect: opencode attach http://%s:%s -u opencode\n' "${WZ_HOST}" "${WZ_PORT}"
        exec opencode serve --port "${WZ_PORT}" --hostname "${WZ_HOST}"
    else
        printf 'connect: opencode attach http://%s:%s -u opencode -p '\''%s'\''\n' \
            "${WZ_HOST}" "${WZ_PORT}" "${WZ_PASS}"
        exec env OPENCODE_SERVER_PASSWORD="${WZ_PASS}" \
            opencode serve --port "${WZ_PORT}" --hostname "${WZ_HOST}"
    fi
}

# Запуск при исполнении или через `bs run` (source'ит скрипт),
# пропуск при ручном source (для тестов).
# Run when executed or via `bs run` (which sources); skip on manual source.
if [[ -n "${BASH_EXECUTION_STRING:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi