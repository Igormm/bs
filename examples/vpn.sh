#!/usr/bin/env bs
# shellcheck shell=bash
# examples/vpn.sh — VPN/proxy client on the sing-box and Xray cores: VLESS (REALITY,
# XHTTP, encryption), VMess, Trojan, Shadowsocks, Hysteria2, Hysteria, TUIC, AnyTLS,
# WireGuard, NaiveProxy, SOCKS; CLI and full-screen TUI
# examples/vpn.sh — VPN/прокси-клиент на ядрах sing-box и Xray: VLESS (REALITY, XHTTP,
# шифрование), VMess, Trojan, Shadowsocks, Hysteria2, Hysteria, TUIC, AnyTLS,
# WireGuard, NaiveProxy, SOCKS; CLI и полноэкранный TUI
#
# Run / Запуск:
#   bs run examples/vpn.sh                 # TUI (в терминале) / TUI (on a terminal)
#   bs run examples/vpn.sh help            # все команды / all commands
#   bs run examples/vpn.sh core install    # скачать sing-box / download sing-box
#   bs run examples/vpn.sh core install xray   # и Xray для XHTTP / and Xray for XHTTP
#   bs run examples/vpn.sh import 'vless://…'
#   bs run examples/vpn.sh connect
#
# Storage: ${BS_VPN_HOME:-~/.config/bs/vpn}; runtime: ${BS_VPN_STATE:-~/.local/state/bs/vpn}.
# Хранилище: ${BS_VPN_HOME:-~/.config/bs/vpn}; состояние: ${BS_VPN_STATE:-~/.local/state/bs/vpn}.

load "lib/network/vpn/tui"

# @private
# @description Print the usage / Вывести справку.
vpn_cli::usage() {
    cat <<'EOF'
BS VPN — клиент на ядрах sing-box и Xray / client on the sing-box and Xray cores

Использование / Usage: vpn.sh [команда] [аргументы]

  tui                        полноэкранный интерфейс (по умолчанию в терминале)
  import <ссылка|файл|->     импорт ссылок vless/vmess/trojan/ss/hy2/hysteria/tuic/anytls/
                             wireguard/naive/socks, подписок и .conf WireGuard
  list [группа]              серверы (● — подключён), задержка последнего замера
  show <id>                  поля профиля
  link <id> [--qr]           ссылка для передачи (и QR-код, если есть qrencode)
  set <id> <поле> <значение> изменить поле профиля (sni, fp, path, host, …)
  rm <id>                    удалить сервер

  connect [id]               подключиться (в группе — переключение без разрыва)
  auto                       автовыбор самого быстрого сервера группы
  disconnect                 отключиться
  status                     состояние, трафик, текущий сервер
  test [id…|--tcp id…]       реальная задержка через ядро (все — без аргументов)
  ip [direct]                внешний IP через туннель (или напрямую)
  logs [-n N] [-f]           журнал ядра

  sub add <имя> <url>        добавить подписку и загрузить её
  sub update [имя]           обновить одну или все подписки
  sub list | sub rm <имя>    список / удаление (вместе с серверами)

  config [id]                показать сгенерированный конфиг ядра (sing-box или Xray)
  settings                   все настройки
  get <ключ> | set-option <ключ> <значение>
                             core auto|sing-box|xray · mode proxy|tun ·
                             route global|bypass-ru|bypass-cn|bypass-ir|direct ·
                             listen_port · allow_lan · dns_remote · dns_direct · block_ads ·
                             direct_domains · proxy_domains · block_domains · tun_stack · ipv6 …

  core info                           ядра: версии и пути
  core install [sing-box|xray] [версия]   загрузка ядра с GitHub (по умолчанию sing-box)
  service install|remove|show         автозапуск через systemd (root)
EOF
}

# @private
vpn_cli::die() {
    printf '%s\n' "$1" >&2
    exit "${2:-1}"
}

# @private
# @description Profile list as an aligned table / Список профилей таблицей.
vpn_cli::list() {
    local -A lat=()
    local id ms _t
    while IFS=$'\t' read -r id ms _t; do lat["${id}"]="${ms}"; done < <(vpn::core::latency_list)
    local active="" live=""
    if vpn::core::running; then
        active="$(vpn::core::session_get id)"
        live="$(vpn::core::current 2>/dev/null)"
        live="${live#auto:}"
    fi
    local proto name server group security transport mark ping
    local -i n=0
    printf '  %s %s %s %s %s\n' "$(vpn::tui::fit ID 18)" "$(vpn::tui::fit PROTO 10)" \
        "$(vpn::tui::fit NAME 28)" "$(vpn::tui::fit SERVER 28)" "PING"
    while IFS=$'\t' read -r id proto name server group security transport; do
        mark=" "
        [[ -n "${active}" && ( "${id}" == "${live}" || ( -z "${live}" && "${id}" == "${active}" ) ) ]] && mark="●"
        ms="${lat[$id]:-}"
        case "${ms}" in
            '') ping="—" ;; -1) ping="fail" ;; -2) ping="bad" ;; *) ping="${ms}ms" ;;
        esac
        printf '%s %s %s %s %s %s\n' "${mark}" "$(vpn::tui::fit "${id}" 18)" \
            "$(vpn::tui::fit "$(vpn::tui::proto_label "${proto}" "${security}" "${transport}")" 10)" \
            "$(vpn::tui::fit "$(vpn::tui::narrow "${name}")" 28)" "$(vpn::tui::fit "${server}" 28)" "${ping}"
        n=$(( n + 1 ))
    done < <(vpn::store::list "${1-}")
    (( n == 0 )) && printf '  (пусто: vpn.sh import <ссылка> или vpn.sh sub add <имя> <url>)\n'
    return 0
}

# @private
vpn_cli::status() {
    local line
    local -A st=()
    while IFS= read -r line; do st["${line%%=*}"]="${line#*=}"; done < <(vpn::core::status)
    if [[ "${st[running]}" != 1 ]]; then
        printf '○ отключено / disconnected · режим %s · маршрут %s · выбран %s\n' \
            "${st[mode]}" "${st[route]}" "${st[id]:-—}"
        return 0
    fi
    printf '● подключено / connected\n'
    local cur
    cur="$(vpn::core::current 2>/dev/null)" || cur="${st[id]}"
    printf '  сервер     %s (%s)\n' "$(vpn::tui::narrow "$(vpn::store::field "${cur#auto:}" name 2>/dev/null)")" "${cur}"
    printf '  ядро       %s\n' "${st[engine]}"
    printf '  режим      %s%s\n' "${st[mode]}" "$([[ "${st[mode]}" == proxy ]] && printf ' · socks5/http %s' "${st[listen]}")"
    printf '  маршрут    %s\n' "${st[route]}"
    printf '  время      %s\n' "$(vpn::tui::duration "${st[uptime]}")"
    local up down conns
    if IFS=' ' read -r up down conns < <(vpn::core::traffic 2>/dev/null); then
        printf '  трафик     ↓ %s  ↑ %s  · соединений %s\n' "$(vpn::tui::bytes "${down}")" "$(vpn::tui::bytes "${up}")" "${conns}"
    fi
    printf '  pid        %s\n' "${st[pid]}"
}

# @private
vpn_cli::import() {
    local -r src="${1:?ссылка, файл или - / link, file or -}" group="${2:-manual}"
    local text
    if [[ "${src}" == "-" ]]; then
        text="$(cat)"
    elif [[ -f "${src}" ]]; then
        text="$(cat -- "${src}")"
    else
        text="${src}"
    fi
    local -a before=() after=()
    mapfile -t before < <(vpn::store::ids)
    vpn::store::import_text "${text}" "${group}" || vpn_cli::die "ссылки не найдены / no valid links" "${LIB_ERROR_INVALID_INPUT}"
    mapfile -t after < <(vpn::store::ids)
    printf 'импортировано / imported: %d (всего / total %d)\n' "$(( ${#after[@]} - ${#before[@]} ))" "${#after[@]}"
}

# @private
vpn_cli::test() {
    local -a ids=()
    if [[ "${1-}" == "--tcp" ]]; then
        shift
        (( $# > 0 )) || mapfile -t ids < <(vpn::store::ids)
        (( $# > 0 )) && ids=("$@")
        local id ms
        for id in "${ids[@]}"; do
            if ms="$(vpn::core::test_tcp "${id}" 2>/dev/null)"; then
                printf '%s\t%sms\n' "${id}" "${ms}"
                vpn::core::latency_save "${id}" "${ms}"
            else
                printf '%s\t%s\n' "${id}" "$([[ $? == "${LIB_ERROR_INVALID_ARGS}" ]] && printf 'udp (нужен реальный тест)' || printf 'fail')"
            fi
        done
        return 0
    fi
    local id ms
    while IFS=$'\t' read -r id ms; do
        case "${ms}" in
            -1) printf '%s\tfail\n' "${id}" ;; -2) printf '%s\tbad (ядро не принимает профиль или не установлено)\n' "${id}" ;;
            *) printf '%s\t%sms\n' "${id}" "${ms}" ;;
        esac
    done < <(vpn::core::test_real "$@")
}

# @private
vpn_cli::sub() {
    local -r cmd="${1:-list}"
    shift || true
    case "${cmd}" in
        add)
            vpn::sub::add "${1-}" "${2-}" || exit $?
            printf 'серверов / servers: %s\n' "$(vpn::sub::update "$1")" ;;
        update)
            local name
            if (( $# > 0 )); then
                printf '%s: %s\n' "$1" "$(vpn::sub::update "$1")"
            else
                while IFS=$'\t' read -r name _; do
                    printf '%s: %s\n' "${name}" "$(vpn::sub::update "${name}" 2>&1)"
                done < <(vpn::sub::list)
            fi ;;
        list|ls)
            local name url updated count
            while IFS=$'\t' read -r name url updated count; do
                printf '%s  %s серв.  %s  %s\n' "$(vpn::tui::fit "${name}" 16)" "${count:-0}" "${updated:-никогда}" "${url}"
            done < <(vpn::sub::list) ;;
        rm|remove) vpn::sub::remove "${1-}" ;;
        *) vpn_cli::die "sub: add|update|list|rm" "${LIB_ERROR_INVALID_ARGS}" ;;
    esac
}

# @private
vpn_cli::core() {
    case "${1:-info}" in
        info)
            local bin engine assets
            local -i found=0
            for engine in sing-box xray; do
                if bin="$(vpn::core::bin "${engine}")"; then
                    printf '%-9s %-10s %s\n' "${engine}" "$(vpn::core::version "${engine}")" "${bin}"
                    found=$(( found + 1 ))
                else
                    printf '%-9s %-10s vpn.sh core install %s\n' "${engine}" "—" "${engine}"
                fi
            done
            if vpn::core::bin xray >/dev/null 2>&1; then
                assets="$(vpn::core::xray_assets)" || assets="нет geoip.dat/geosite.dat / no geo files"
                printf '%-9s %-10s %s\n' "" "geo" "${assets}"
            fi
            (( found > 0 )) || return "${LIB_ERROR_DEPENDENCY_MISSING}" ;;
        install)
            local path engine="${2:-sing-box}"
            [[ "${engine}" =~ ^v?[0-9] ]] && engine="sing-box"
            path="$(vpn::core::install "${@:2}")" || exit $?
            printf 'установлено / installed: %s (%s)\n' "${path}" "$(vpn::core::version "${engine}")" ;;
        *) vpn_cli::die "core: info|install [sing-box|xray] [версия]" "${LIB_ERROR_INVALID_ARGS}" ;;
    esac
}

# @private
vpn_cli::logs() {
    local -i n=50 follow=0
    while (( $# > 0 )); do
        case "$1" in
            -n) n="${2:-50}"; shift 2 ;;
            -f) follow=1; shift ;;
            *) shift ;;
        esac
    done
    if (( follow == 1 )); then
        tail -n "${n}" -F "$(vpn::core::log_file)"
    else
        vpn::core::log_tail "${n}" | while IFS= read -r line; do vpn::tui::__strip_sgr "${line}"; printf '\n'; done
    fi
}

main() {
    local cmd="${1-}"
    if [[ -z "${cmd}" ]]; then
        if [[ -t 0 && -t 1 ]]; then cmd="tui"; else cmd="help"; fi
    fi
    shift || true
    case "${cmd}" in
        tui) vpn::tui::run ;;
        help|-h|--help) vpn_cli::usage ;;
        import|add) vpn_cli::import "$@" ;;
        list|ls) vpn_cli::list "$@" ;;
        show) vpn::store::get "${1-}" ;;
        link)
            local link
            link="$(vpn::store::get "${1-}" | vpn::link::build)" || exit $?
            printf '%s\n' "${link}"
            [[ "${2-}" == "--qr" ]] && is::command qrencode && qrencode -t ANSIUTF8 -- "${link}" ;;
        set) vpn::store::set_field "${1-}" "${2-}" "${3-}" ;;
        rm|remove|del) vpn::store::remove "${1-}" ;;
        connect|up|start)
            if (( $# > 0 )); then vpn::core::switch "$1" || exit $?; else vpn::core::start || exit $?; fi
            vpn_cli::status ;;
        auto)
            vpn::settings::set auto_select 1 >/dev/null
            if vpn::core::running; then vpn::core::switch auto; else vpn::core::start; fi
            vpn_cli::status ;;
        disconnect|down|stop) vpn::core::stop; printf 'отключено / disconnected\n' ;;
        restart) vpn::core::start "$(vpn::settings::get active)" && vpn_cli::status ;;
        status) vpn_cli::status ;;
        test|ping) vpn_cli::test "$@" ;;
        ip)
            local ip country city org
            IFS=' ' read -r ip country city org < <(vpn::core::exit_ip "${1-}") || vpn_cli::die "не удалось / failed" "${LIB_ERROR_TIMEOUT}"
            printf '%s  %s %s  %s\n' "${ip}" "${country}" "${city//_/ }" "${org//_/ }" ;;
        logs|log) vpn_cli::logs "$@" ;;
        sub) vpn_cli::sub "$@" ;;
        config)
            local id="${1:-$(vpn::settings::get active)}" engine
            is::empty "${id}" && id="$(vpn::store::ids | sed -n 1p)"
            engine="$(vpn::core::engine_for "${id}")" || exit $?
            local -a ids=()
            mapfile -t ids < <(vpn::core::config_ids "${id}" "${engine}")
            if [[ "${engine}" == "xray" ]]; then
                vpn::core::xray_assets >/dev/null && VPN_XRAY_GEO=1
                vpn::xray::config "${ids[@]}"
            else
                vpn::core::require sing-box 2>/dev/null || VPN_SINGBOX_VERSION=""
                vpn::singbox::config "${ids[@]}"
            fi ;;
        settings) vpn::settings::list ;;
        get) vpn::settings::get "${1:?ключ / key}" ;;
        set-option|option) vpn::settings::set "${1:?ключ / key}" "${2-}" && printf '%s=%s (применится при переподключении / applies on reconnect)\n' "$1" "${2-}" ;;
        core) vpn_cli::core "$@" ;;
        service)
            case "${1:-show}" in
                install) vpn::core::service_install ;;
                remove) vpn::core::service_remove ;;
                show) vpn::core::service_unit ;;
                *) vpn_cli::die "service: install|remove|show" "${LIB_ERROR_INVALID_ARGS}" ;;
            esac ;;
        *) vpn_cli::usage >&2; exit "${LIB_ERROR_INVALID_ARGS}" ;;
    esac
}

if bs::is_main; then
    main "$@"
fi
