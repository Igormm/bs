#!/usr/bin/env bs
# shellcheck shell=bash
# examples/opencode_serve_wizard.sh — interactive wizard for the opencode server
# examples/opencode_serve_wizard.sh — интерактивный визард для opencode-сервера
#
# Centered full-screen wizard built on the shared BS wizard engine
# (lib/ui/wizard): chooses the bind IP (auto-detect / interface / explicit),
# port and password, then launches `opencode serve`. The engine is the same
# as in examples/ai_user_wizard.sh (wizard::menu/ask_input/ask_pass/intro/
# box/yn/alert) — raw-ANSI frames, safe key handling (unknown keys ignored,
# q cancels, a stray ESC is a safe no-op), the terminal is restored on any
# exit, resizes are handled per frame.
# Центрированный полноэкранный визард на общем движке BS (lib/ui/wizard):
# выбор IP (авто / интерфейс / явный), порта и пароля, затем запуск
# `opencode serve`. Движок тот же, что в examples/ai_user_wizard.sh
# (wizard::menu/ask_input/ask_pass/intro/box/yn/alert) — raw-ANSI рамки,
# безопасная обработка клавиш (неизвестные игнорируются, отмена — q,
# одиночный ESC — безопасный no-op), терминал восстанавливается при любом
# выходе, resize обрабатывается каждый кадр.
#
# Run / Запуск:
#   bs run examples/opencode_serve_wizard.sh
#   ./examples/opencode_serve_wizard.sh
#
# Keys / Клавиши:
#   ↑/↓ — выбор · Enter — OK · q — отмена/выход

load "core/utils"
load "lib/ui/wizard"
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

# @private Explicit IP step (validates, retries) / Шаг «явный IP» (с проверкой).
# @return 0 ok, 1 cancelled / 0 успех, 1 отмена
wz::step_ip() {
    local value
    while true; do
        wizard::ask_input value "IP сервера / Server IP  (например / e.g. 192.168.1.50)" "" \
            "IP, по которому к серверу будут подключаться / the IP clients connect to"
        [[ "${value}" == "q" ]] && return 1
        if wz::validate_ipv4 "${value}"; then
            WZ_IP="${value}"
            WZ_SOURCE="ip"
            return 0
        fi
        wizard::alert "Неверный IP / Invalid IP: ${value}" >/dev/null || true
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
        wizard::alert "Нет интерфейсов с IPv4 / No interfaces with IPv4" >/dev/null || true
        return 1
    fi

    local pick
    wizard::menu pick "Сетевой интерфейс / Network interface" "" "${wz_items[@]}"
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
        wizard::ask_input value "Порт сервера / Server port" "${WZ_PORT}" \
            "По этому порту подключаетесь: http://IP:порт / connect via http://IP:port"
        [[ "${value}" == "q" ]] && return 1
        if [[ "${value}" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 65535 )); then
            WZ_PORT="${value}"
            return 0
        fi
        wizard::alert "Порт должен быть числом 1-65535 / Port must be 1-65535: ${value}" >/dev/null || true
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
    wizard::menu pick "Пароль сервера / Server password" \
        "Пароль для подключения к серверу / Server access password" \
        "Сгенерировать / Generate" \
        "Ввести свой / Enter my own" \
        "Без пароля (НЕБЕЗОПАСНО / UNSECURED)"
    [[ "${pick}" == "99" ]] && return 1
    case "${pick}" in
        0)
            WZ_PASS="$(wizard::gen_pass)"
            WZ_PASS_MODE="generated"
            ;;
        1)
            wizard::ask_pass pass "Пароль для подключения к серверу / Password used to connect"
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

# @private Summary + confirm / Сводка + подтверждение.
# @return 0 yes, 1 no/cancelled / 0 да, 1 нет/отмена
wz::step_confirm() {
    local mode_desc pass_desc
    case "${WZ_SOURCE}" in
        auto)  mode_desc="автоопределение / auto-detect" ;;
        iface) mode_desc="интерфейс ${WZ_IFACE} / interface ${WZ_IFACE}" ;;
        ip)    mode_desc="указанный IP / explicit IP" ;;
    esac
    case "${WZ_PASS_MODE}" in
        generated) pass_desc="сгенерирован / generated" ;;
        entered)   pass_desc="введён / entered" ;;
        env)       pass_desc="из окружения / from env" ;;
        none)      pass_desc="нет / none (НЕБЕЗОПАСНО / UNSECURED)" ;;
    esac

    local summary
    printf -v summary "%s\n" \
        "IP:        ${WZ_HOST}" \
        "Источник:  ${mode_desc}" \
        "Порт:      ${WZ_PORT}" \
        "Пароль:    ${pass_desc}" \
        "Подключение / Connect:" \
        "  opencode attach http://${WZ_HOST}:${WZ_PORT} -u opencode -p '...'"
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        summary+=$'\n'"Файрвол / Firewall: sudo firewall-cmd --add-port=${WZ_PORT}/tcp --permanent && sudo firewall-cmd --reload"
    fi

    wizard::box "Сводка / Summary" "${summary}"
    local start
    wizard::yn start "Запустить? / Start?" ""
    case "${start}" in
        y) return 0 ;;
        *) return 1 ;;
    esac
}

# ==========================================
# Main / Главная
# ==========================================

main() {
    # -h/--help: справка без запуска визарда / usage without starting the wizard
    case "${1:-}" in
        -h|--help)
            printf 'Usage: bs run examples/opencode_serve_wizard.sh\n'
            printf '       ./examples/opencode_serve_wizard.sh\n\n'
            printf 'Интерактивный визард запуска opencode-сервера (IP → порт → пароль → запуск).\n'
            printf 'Interactive wizard for starting the opencode server (IP → port → password → run).\n\n'
            printf 'Keys / Клавиши: ↑/↓ — выбор · Enter — OK · q — отмена/выход\n'
            exit 0
            ;;
    esac

    # ---- opencode installed? / opencode установлен?
    if ! is::command opencode; then
        wizard::__enter_alt
        wizard::alert "opencode не установлен / not installed — https://opencode.ai" >/dev/null || true
        wizard::__restore
        exit 1
    fi

    wizard::__enter_alt

    # ---- welcome / приветствие
    if ! wizard::intro "opencode server — визард / wizard" \
        "Запуск сервера opencode с basic auth." \
        "Шаги: IP → порт → пароль → запуск." \
        "Steps: IP → port → password → run."; then
        wizard::__restore
        exit 0
    fi

    # ---- авто-IP для подсказки / auto IP for the hint
    WZ_AUTO_IP="$(utils::attempt system::utils::get_ip_address)"

    # ---- шаг 1: источник IP / IP source
    local pick
    while true; do
        if is::empty "${WZ_AUTO_IP}"; then
            wizard::menu pick "Откуда брать IP / IP source" \
                "IP, на котором сервер будет слушать / the IP the server listens on" \
                "Автоопределение / Auto-detect" \
                "Сетевой интерфейс / Network interface" \
                "Указанный IP / Explicit IP"
        else
            wizard::menu pick "Откуда брать IP / IP source" \
                "IP, на котором сервер будет слушать / the IP the server listens on" \
                "Автоопределение / Auto-detect (${WZ_AUTO_IP})" \
                "Сетевой интерфейс / Network interface" \
                "Указанный IP / Explicit IP"
        fi
        [[ "${pick}" == "99" ]] && { wizard::__restore; exit 0; }
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
    wz::step_port || { wizard::__restore; exit 0; }

    # ---- шаг 3: пароль / password
    wz::step_pass || { wizard::__restore; exit 0; }

    # ---- итоговый host / final hostname
    if is::empty "${WZ_IP}"; then
        WZ_HOST="0.0.0.0"
    else
        WZ_HOST="${WZ_IP}"
    fi

    # ---- сводка / summary
    if ! wz::step_confirm; then
        wizard::__restore
        exit 0
    fi

    # ---- запуск / launch
    wizard::__restore
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