#!/usr/bin/env bs
# shellcheck shell=bash
# examples/opencode_serve.sh — helper for the opencode server task
# examples/opencode_serve.sh — помощник для задачи «opencode-сервер»
#
# Проверяет, что opencode установлен (is::command), предупреждает про sudo
# (нужен только для файрвола и systemd — не для самого сервера), и запускает
# сервер с basic auth. IP машины определяется автоматически (hostname -I),
# либо задаётся явно флагом --ip / --iface; найденный IP передаётся как
# --hostname, чтобы opencode напечатал в баннере реальный адрес, а не 0.0.0.0.
# Checks that opencode is installed (is::command), warns about sudo (needed
# only for the firewall and systemd — not for the server itself), then starts
# the server with basic auth. The machine IP is auto-detected (hostname -I),
# or set explicitly via --ip / --iface; the detected IP is passed as
# --hostname so opencode prints the real address in its banner, not 0.0.0.0.
#
# Запуск / Run:
#   OPENCODE_SERVER_PASSWORD='пароль' bs run examples/opencode_serve.sh
#   OPENCODE_SERVER_PASSWORD='пароль' bs run examples/opencode_serve.sh --ip 192.168.1.50
#   OPENCODE_SERVER_PASSWORD='пароль' bs run examples/opencode_serve.sh --iface wlan0
#   OPENCODE_SERVER_PASSWORD='пароль' ./examples/opencode_serve.sh --ip 192.168.1.50
#   bs run examples/opencode_serve.sh --wizard        # интерактивный визард / interactive wizard

load "core/args"
load "core/logger"
load "core/lang"
load "core/utils"
load "lib/system/utils"

readonly PORT="${PORT:-4096}"

# @private
# @description IPv4 format validator for the --ip flag / Валидатор формата IPv4 для флага --ip
# @param $1 Value to check / Проверяемое значение
# @return 0 if valid, 1 otherwise / 0 если корректно, иначе 1
validate_ipv4() {
    local -r value="${1:-}"
    local -a octets=()
    local octet
    [[ "${value}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return "${E_ERROR:-1}"
    local IFS='.'
    read -ra octets <<< "${value}"
    for octet in "${octets[@]}"; do
        (( 10#${octet} <= 255 )) || return "${E_ERROR:-1}"
    done
    return "${E_SUCCESS:-0}"
}

main() {
    args::flag wizard
    args::flag ip value "" validate_ipv4
    args::flag iface value
    args::flag_describe wizard "Launch the interactive wizard / Запустить интерактивный визард"
    args::flag_describe ip "Explicit local IP (default: auto-detect; 0.0.0.0 = all interfaces) / Явный IP (по умолчанию: автоопределение; 0.0.0.0 = все интерфейсы)"
    args::flag_describe iface "Get the IP from this network interface / Взять IP этого сетевого интерфейса"
    args::require "$@"

    # 0. Режим визарда / Wizard mode: запускаем интерактивный визард.
    if args::flag_is_set wizard; then
        local -r wz_dir="$(bs::script_dir)"
        local -r wz_script="${wz_dir}/opencode_serve_wizard.sh"
        if ! is::file "${wz_script}"; then
            log::error "wizard not found / визард не найден: ${wz_script}"
            exit 1
        fi
        exec bs run "${wz_script}"
    fi

    # 1. Проверка существования пакета / Check the package exists
    if ! is::command opencode; then
        log::error "opencode is not installed / opencode не установлен"
        log::error "install it first / сначала установите: https://opencode.ai"
        exit 1
    fi
    log::info "opencode found: $(command -v opencode)"

    # 2. Пароль обязателен / Password is mandatory
    if is::empty "${OPENCODE_SERVER_PASSWORD:-}"; then
        log::error "OPENCODE_SERVER_PASSWORD is not set / пароль не задан"
        log::error "run: OPENCODE_SERVER_PASSWORD='ваш-пароль' bs run examples/opencode_serve.sh"
        exit 1
    fi

    # 3. Предупреждение про sudo / Warn about sudo
    #    Сам сервер root НЕ требует (порт 4096 > 1024), но шаги файрвола и
    #    systemd — требуют. Проверяем и предупреждаем заранее.
    #    The server itself does NOT need root (port 4096 > 1024), but the
    #    firewall and systemd steps do. Check and warn up front.
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        log::warn "you are not root — this is fine for the server itself"
        log::warn "вы не root — для самого сервера это нормально"
        log::warn "sudo is needed ONLY for: / sudo нужен ТОЛЬКО для:"
        log::warn "  1) firewall: sudo firewall-cmd --add-port=${PORT}/tcp --permanent && sudo firewall-cmd --reload"
        log::warn "  2) optional autostart: sudo systemctl enable --now opencode"
    else
        log::warn "running as root — the server will accept connections on the host address"
        log::warn "запуск от root — сервер будет принимать подключения на адресе хоста"
    fi

    # 4. Определяем IP машины / Detect the machine IP
    #    Приоритет: --ip > --iface > автоопределение (hostname -I).
    #    hostname -I отдаёт актуальный адрес (может меняться — 192.168.1.x).
    #    Priority: --ip > --iface > auto-detect (hostname -I).
    #    hostname -I returns the current address (it can change — 192.168.1.x).
    local ip=""
    if args::flag_is_set ip; then
        ip="$(args::flag_get ip)"
        log::info "using explicit IP from --ip / используем IP из --ip: ${ip}"
    elif args::flag_is_set iface; then
        local iface
        iface="$(args::flag_get iface)"
        ip="$(utils::attempt system::utils::get_ip_address_for_interface "${iface}")"
        if is::empty "${ip}"; then
            log::warn "no IPv4 address on interface '${iface}' / на интерфейсе '${iface}' нет IPv4-адреса"
        else
            log::info "IP of interface ${iface} / IP интерфейса ${iface}: ${ip}"
        fi
    else
        ip="$(utils::attempt system::utils::get_ip_address)"
        if is::empty "${ip}"; then
            log::warn "could not detect local IP / не удалось определить локальный IP"
            log::info "hint: pass it explicitly / подсказка: укажите явно: --ip 192.168.1.50 или --iface wlan0"
        else
            log::info "your machine IP / IP вашей машины: ${ip}"
        fi
    fi

    # 5. Запуск сервера / Start the server
    #    --hostname = реальный IP: opencode напечатает в баннере
    #    "listening on http://<ip>:<port>", а не "0.0.0.0:port", который
    #    с другой машины недоступен. Если IP определить не удалось —
    #    слушаем 0.0.0.0 (все интерфейсы).
    #    --hostname = the real IP: opencode prints "listening on
    #    http://<ip>:<port>" in its banner instead of "0.0.0.0:port", which
    #    is not reachable from another machine. If detection fails — listen
    #    on 0.0.0.0 (all interfaces).
    local hostname="0.0.0.0"
    if is::not_empty "${ip}"; then
        hostname="${ip}"
    fi
    if is::empty "${ip}"; then
        log::info "starting opencode serve on 0.0.0.0:${PORT} ..."
        log::info "opencode serve запускается на 0.0.0.0:${PORT} ..."
        log::info "find your IP manually: ip -4 a   (e.g. 192.168.1.50)"
        log::info "from another machine: opencode attach http://<ip>:${PORT} -u opencode -p 'пароль'"
    else
        log::info "starting opencode serve on http://${hostname}:${PORT} ..."
        log::info "opencode serve запускается на http://${hostname}:${PORT} ..."
        log::info "from another machine: opencode attach http://${hostname}:${PORT} -u opencode -p 'пароль'"
        log::info "с другой машины: opencode attach http://${hostname}:${PORT} -u opencode -p 'пароль'"
    fi
    exec env OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD}" \
        opencode serve --port "${PORT}" --hostname "${hostname}"
}

main "$@"