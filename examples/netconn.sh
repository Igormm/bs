#!/usr/bin/env bs
# shellcheck shell=bash
# examples/netconn.sh — network connections: interfaces, NetworkManager profiles, Wi-Fi; CLI and full-screen TUI
# examples/netconn.sh — сетевые подключения: интерфейсы, профили NetworkManager, Wi-Fi; CLI и полноэкранный TUI
#
# Run / Запуск:
#   bs run examples/netconn.sh                 # TUI (в терминале) / TUI (on a terminal)
#   bs run examples/netconn.sh help            # все команды / all commands
#   bs run examples/netconn.sh list
#   bs run examples/netconn.sh show eth0
#   bs run examples/netconn.sh wifi connect "Home" --ask

load "lib/network/conn/tui"

# @private
# @description Print the usage / Вывести справку.
netconn_cli::usage() {
    cat <<'EOF'
BS NET — сетевые подключения / network connections

Использование / Usage: netconn.sh [команда] [аргументы]

  tui [if|nm|wifi]           полноэкранный интерфейс (по умолчанию в терминале)
  list                       интерфейсы: имя, вид, состояние, MAC, MTU, IPv4
  show <интерфейс>           сведения: адреса, шлюз, скорость, драйвер, счётчики
  up <интерфейс>             поднять (nmcli, иначе ip link set up — нужен root)
  down <интерфейс>           опустить
  routes                     маршруты по умолчанию и DNS

  profiles                   профили NetworkManager (● — активен)
  connect <профиль|uuid>     включить профиль
  disconnect <профиль|uuid>  выключить профиль

  wifi [list]                видимые сети Wi-Fi
  wifi rescan                искать заново
  wifi connect <ssid> [--ask|--password-stdin] [--ifname <if>]
                             подключиться; пароль спрашивается, а не берётся из аргументов
  wifi on | wifi off         включить или выключить радио Wi-Fi

  help                       эта справка

Без NetworkManager работают list/show/routes и up/down через iproute2.
Without NetworkManager, list/show/routes and up/down (iproute2) still work.
EOF
}

# @private
# @description Print an error and exit / Вывести ошибку и выйти.
netconn_cli::die() {
    printf 'netconn: %s\n' "$1" >&2
    exit "${2:-1}"
}

# @private
netconn_cli::list() {
    local name kind state mac mtu addr dot
    local -A ip4=()
    if is::command ip; then
        while IFS=' ' read -r name addr; do
            [[ -n "${name}" && -z "${ip4[${name}]:-}" ]] && ip4["${name}"]="${addr}"
        done < <(ip -o -4 addr show 2>/dev/null | awk '{print $2, $4}')
    fi
    printf '  %-16s %-10s %-9s %-18s %-6s %s\n' "NAME" "KIND" "STATE" "MAC" "MTU" "IPv4"
    while IFS=$'\t' read -r name kind state mac mtu; do
        dot="○"
        [[ "${state}" == up ]] && dot="●"
        printf '%s %-16s %-10s %-9s %-18s %-6s %s\n' "${dot}" "${name}" "${kind}" "${state}" "${mac}" "${mtu}" "${ip4[${name}]:--}"
    done < <(network::conn::list)
}

# @private
netconn_cli::routes() {
    local dev gw metric
    printf 'Маршруты по умолчанию / default routes:\n'
    local -i n=0
    while IFS=$'\t' read -r dev gw metric; do
        printf '  via %-15s dev %-12s metric %s\n' "${gw}" "${dev}" "${metric}"
        n=$(( n + 1 ))
    done < <(network::conn::gateways)
    (( n > 0 )) || printf '  нет / none\n'
    printf 'DNS:\n'
    local s
    n=0
    while IFS= read -r s; do printf '  %s\n' "${s}"; n=$(( n + 1 )); done < <(network::conn::dns)
    (( n > 0 )) || printf '  нет / none\n'
}

# @private
netconn_cli::profiles() {
    network::conn::nm::available || netconn_cli::die "NetworkManager не запущен / not running" 1
    local name uuid type dev active dot
    printf '  %-28s %-20s %-12s %s\n' "NAME" "TYPE" "DEVICE" "UUID"
    while IFS=$'\t' read -r name uuid type dev active; do
        dot="○"
        [[ "${active}" == yes ]] && dot="●"
        printf '%s %-28s %-20s %-12s %s\n' "${dot}" "${name}" "${type}" "${dev}" "${uuid}"
    done < <(network::conn::nm::profiles)
}

# @private
netconn_cli::wifi_list() {
    local inuse ssid signal sec chan
    printf '  %-32s %-9s %-5s %s\n' "SSID" "SIGNAL" "CHAN" "SECURITY"
    while IFS=$'\t' read -r inuse ssid signal sec chan; do
        [[ "${inuse}" == '*' ]] || inuse=" "
        [[ "${sec}" == "--" ]] && sec="open"
        printf '%s %-32s %s %3s%% %-5s %s\n' "${inuse}" "${ssid}" "$(network::conn::tui::bars "${signal}")" "${signal}" "${chan}" "${sec}"
    done < <(network::conn::wifi::scan "${1:-auto}")
}

# @private
# @description wifi connect <ssid> [--ask|--password-stdin] [--ifname IF]
netconn_cli::wifi_connect() {
    local ssid="" pass="" ifc="" mode=""
    while (( $# > 0 )); do
        case "$1" in
            --ask|-p) mode="ask" ;;
            --password-stdin) mode="stdin" ;;
            --ifname|-i) ifc="${2:?--ifname: интерфейс / interface}"; shift ;;
            -*) netconn_cli::die "неизвестный флаг / unknown flag: $1" 2 ;;
            *) [[ -z "${ssid}" ]] && ssid="$1" || netconn_cli::die "лишний аргумент / extra argument: $1" 2 ;;
        esac
        shift
    done
    [[ -n "${ssid}" ]] || netconn_cli::die "wifi connect <ssid> [--ask|--password-stdin]" 2
    case "${mode}" in
        ask)
            [[ -t 0 ]] || netconn_cli::die "--ask нужен терминал / needs a terminal; use --password-stdin" 2
            IFS= read -r -s -p "Пароль «${ssid}» / password: " pass
            printf '\n' ;;
        stdin) IFS= read -r pass || : ;;
    esac
    network::conn::wifi::connect "${ssid}" "${pass}" "${ifc}"
}

main() {
    local cmd="${1-}"
    if [[ -z "${cmd}" ]]; then
        if [[ -t 0 && -t 1 ]]; then cmd="tui"; else cmd="list"; fi
    fi
    shift || true
    case "${cmd}" in
        tui) network::conn::tui::run "${1:-if}" ;;
        help|-h|--help) netconn_cli::usage ;;
        list|ls) netconn_cli::list ;;
        show) network::conn::show "${1:?show <интерфейс / interface>}" ;;
        up) network::conn::up "${1:?up <интерфейс / interface>}" ;;
        down) network::conn::down "${1:?down <интерфейс / interface>}" ;;
        routes|route) netconn_cli::routes ;;
        profiles|conns) netconn_cli::profiles ;;
        connect) network::conn::nm::up "${1:?connect <профиль / profile>}" ;;
        disconnect) network::conn::nm::down "${1:?disconnect <профиль / profile>}" ;;
        wifi)
            local sub="${1:-list}"
            shift || true
            case "${sub}" in
                list|ls) netconn_cli::wifi_list auto ;;
                rescan|scan) netconn_cli::wifi_list yes ;;
                connect) netconn_cli::wifi_connect "$@" ;;
                on|off) network::conn::wifi::radio "${sub}" ;;
                *) netconn_cli::die "wifi: list|rescan|connect|on|off" 2 ;;
            esac ;;
        *) netconn_cli::usage >&2; exit 2 ;;
    esac
}

if bs::is_main; then
    main "$@"
fi
